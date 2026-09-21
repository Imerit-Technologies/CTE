WITH
param AS (
    SELECT organization_id, project_id, project_type
    FROM (VALUES
        ROW('69653d3b2e04320329fd30cb', '697401b14a33e0719d081060', 'ango'),
        ROW('69653d3b2e04320329fd30cb', '6979439fa2a49b048a51e016', 'ango_pct')
    ) AS t(organization_id, project_id, project_type)
),
-- Single dedup scan of gclogs, reused everywhere
gcl_raw AS (
    SELECT *
    FROM (
        SELECT g.*, p.project_type,
            ROW_NUMBER() OVER (PARTITION BY labeltaskid, document_id ORDER BY updatedat DESC) AS rn
        FROM "curated-datalake-prod".gclogs g
        JOIN param p ON g.organization_id = p.organization_id AND g.project_id = p.project_id
        WHERE g.year >= '2025'
    )
    WHERE rn = 1
),
gcl_agg AS (
    SELECT
        g.organization_id, g.project_id, g.project_type,
        g.labeltaskid, g.document_id, g.stage, g.updatedby,
        FROM_UNIXTIME(updatedat + 19500) AS updatedat_date
    FROM gcl_raw g
),
gcl_base AS (
    SELECT project_type, organization_id, project_id, labeltaskid, document_id,
           stage, updatedby, updatedat_date
    FROM gcl_agg
),

-- Ango Stack starts here --
t_raw AS (
    SELECT t.project_id, t.labeltaskid, t.document_id, t.page, t.object_id
    FROM "curated-datalake-prod".tools t
    JOIN param p ON t.organization_id = p.organization_id AND t.project_id = p.project_id
    WHERE p.project_type = 'ango'
    AND t.year >= '2025'
),
gt_raw AS (
    SELECT g.project_type, g.organization_id, g.project_id, g.labeltaskid,
          g.document_id, g.stage, g.updatedby, g.updatedat_date, t.page, t.object_id
    FROM gcl_base g
    JOIN t_raw t ON g.document_id = t.document_id
),
-- Ango Stack ends here --

-- Ango PCT Stack starts here --
apt_raw AS (
	SELECT 
        t.organization_id,
        t.project_id,
        REPLACE(batch_code, 'BC-', '') AS labeltaskid,
        task_code AS document_id,
        t.node,
        FROM_UNIXTIME((start_timestamp+19500)/1000) AS start_time,
        FROM_UNIXTIME((timestamp+19500)/1000) AS end_time,
        user,
        CAST(sequence_num AS INTEGER) AS sequence_num,
        annotations
	FROM "curated-datalake-prod".table_ango_pct_task t
	JOIN param p
	    ON t.organization_id = p.organization_id
	   AND t.project_id = p.project_id
	WHERE t.year >= '2025'
),
apa_raw AS (
    SELECT 
        a.id,
        a.class,
        CONCAT(a.object_type, a.class, '_', CAST(a.identity AS VARCHAR)) AS shape_class_identity,
		CONCAT(
    			CAST(FLOOR("geometry.rotation.x" * 1e5) / 1e5 AS VARCHAR), ',',
    			CAST(FLOOR("geometry.rotation.y" * 1e5) / 1e5 AS VARCHAR), ',',
    			CAST(FLOOR("geometry.rotation.z" * 1e5) / 1e5 AS VARCHAR), ',',
    			CAST(FLOOR("geometry.boxsize.x" * 1e5) / 1e5 AS VARCHAR), ',',
    			CAST(FLOOR("geometry.boxsize.y" * 1e5) / 1e5 AS VARCHAR), ',',
    			CAST(FLOOR("geometry.boxsize.z" * 1e5) / 1e5 AS VARCHAR), ',',
    			CAST(FLOOR("geometry.position.x" * 1e5) / 1e5 AS VARCHAR), ',',
    			CAST(FLOOR("geometry.position.y" * 1e5) / 1e5 AS VARCHAR), ',',
    			CAST(FLOOR("geometry.position.z" * 1e5) / 1e5 AS VARCHAR)
    	) AS combo_coordinate,
        a.object_type,
        a.object_id
    FROM "curated-datalake-prod".table_ango_pct_annotations a
    JOIN param p
        ON a.organization_id = p.organization_id
      AND a.project_id = p.project_id
    WHERE a.year >= '2025'
),
apta_raw AS (
    SELECT 
        p.project_type,
        t.organization_id,
        t.project_id,
        t.labeltaskid,
        t.document_id,
        t.node AS stage,
        t.user AS updatedby,
        t.end_time AS updatedat_date,
        t.sequence_num AS page,
        a.object_id
    FROM apt_raw t
    JOIN apa_raw a
        ON t.annotations = a.id
    JOIN param p
        ON t.organization_id = p.organization_id
      AND t.project_id = p.project_id
),
-- Ango PCT Stack ends here --

-- Combined base starts here --
combined_base_raw AS (
    SELECT * FROM gt_raw
    UNION ALL 
    SELECT * FROM apta_raw
),
stage_flow AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY organization_id, project_id, labeltaskid ORDER BY updatedat_date) AS stage_flow
    FROM (
        SELECT
            project_type,
            organization_id,
            project_id,
            labeltaskid,
            document_id,
            MAX(updatedat_date) AS updatedat_date
        FROM combined_base_raw
        GROUP BY 1, 2, 3, 4, 5
    )
),
stagename AS (
    SELECT project_id, stage, stagename
    FROM gcl_raw
    GROUP BY 1, 2, 3
),
projectname AS (
    SELECT g.project_id, max_by(g.projectname, g.updatedat) AS projectname
    FROM gcl_raw g
    JOIN param p ON g.organization_id = p.organization_id AND g.project_id = p.project_id
    GROUP BY 1
),
combined_base AS (
    SELECT
        b.project_type,
        b.organization_id,
        pn.projectname,
        b.project_id,
        b.labeltaskid,
        b.document_id,
        b.updatedby,
        b.updatedat_date,
        s.stagename,
        sf.stage_flow,
        b.page,
        b.object_id
    FROM
        combined_base_raw b
    LEFT JOIN stagename s ON b.stage = s.stage AND b.project_id = s.project_id
    LEFT JOIN projectname pn ON b.project_id = pn.project_id
    LEFT JOIN stage_flow sf 
        ON b.document_id = sf.document_id 
        AND b.labeltaskid = sf.labeltaskid 
        AND b.project_id = sf.project_id
),
-- Combined base Ends here --

-- Reused, filtered to only the stages we actually need downstream --
combined_base_filtered AS (
    SELECT *
    FROM combined_base
    WHERE stagename IN ('Label', 'Review')
),

task_stage_base AS (
    SELECT DISTINCT
        project_type, organization_id, projectname, project_id,
        labeltaskid, stagename, stage_flow
    FROM combined_base_filtered
),

-- Label last submission starts here --
first_label_flow_calc AS (
    SELECT labeltaskid, MIN(stage_flow) AS first_label_flow
    FROM task_stage_base
    WHERE stagename = 'Label'
    GROUP BY labeltaskid
),
label_block_end_calc AS (
    SELECT 
        b.labeltaskid,
        MIN(CASE WHEN b.stagename <> 'Label' AND b.stage_flow > f.first_label_flow THEN b.stage_flow END) AS next_change_flow
    FROM task_stage_base b
    JOIN first_label_flow_calc f ON b.labeltaskid = f.labeltaskid
    GROUP BY b.labeltaskid
),
last_label_flow_calc AS (
    SELECT 
        b.labeltaskid,
        MAX(b.stage_flow) AS last_label_flow
    FROM task_stage_base b
    JOIN first_label_flow_calc f ON b.labeltaskid = f.labeltaskid
    LEFT JOIN label_block_end_calc e ON b.labeltaskid = e.labeltaskid
    WHERE b.stagename = 'Label'
      AND b.stage_flow >= f.first_label_flow
      AND (e.next_change_flow IS NULL OR b.stage_flow < e.next_change_flow)
    GROUP BY b.labeltaskid
),
last_label_submission AS (
    SELECT 
        c.project_type,
        c.organization_id,
        c.projectname,
        c.project_id,
        c.labeltaskid,
        c.document_id,
        c.updatedby,
        c.updatedat_date,
        c.page,
        c.object_id
    FROM combined_base_filtered c
    JOIN last_label_flow_calc llb
        ON c.labeltaskid = llb.labeltaskid
       AND c.stage_flow = llb.last_label_flow
),
-- Label last submission ends here --

-- Review last submission starts here --
first_review_flow_calc AS (
    SELECT labeltaskid, MIN(stage_flow) AS first_review_flow
    FROM task_stage_base
    WHERE stagename = 'Review'
    GROUP BY labeltaskid
),
review_block_end_calc AS (
    SELECT 
        b.labeltaskid,
        MIN(CASE WHEN b.stagename <> 'Review' AND b.stage_flow > f.first_review_flow THEN b.stage_flow END) AS next_change_flow
    FROM task_stage_base b
    JOIN first_review_flow_calc f ON b.labeltaskid = f.labeltaskid
    GROUP BY b.labeltaskid
),
last_review_flow_calc AS (
    SELECT 
        b.labeltaskid,
        MAX(b.stage_flow) AS last_review_flow
    FROM task_stage_base b
    JOIN first_review_flow_calc f ON b.labeltaskid = f.labeltaskid
    LEFT JOIN review_block_end_calc e ON b.labeltaskid = e.labeltaskid
    WHERE b.stagename = 'Review'
      AND b.stage_flow >= f.first_review_flow
      AND (e.next_change_flow IS NULL OR b.stage_flow < e.next_change_flow)
    GROUP BY b.labeltaskid
),
last_review_submission AS (
    SELECT 
        c.project_type,
        c.organization_id,
        c.projectname,
        c.project_id,
        c.labeltaskid,
        c.document_id,
        c.updatedby,
        c.updatedat_date,
        c.page,
        c.object_id
    FROM combined_base_filtered c
    JOIN last_review_flow_calc lrb
        ON c.labeltaskid = lrb.labeltaskid
       AND c.stage_flow = lrb.last_review_flow
),
-- Review last submission ends here --

valid_labeltaskids AS (
    SELECT DISTINCT labeltaskid FROM last_label_submission
    INTERSECT
    SELECT DISTINCT labeltaskid FROM last_review_submission
),
label_review_join AS (
    SELECT
        COALESCE(l.project_type, r.project_type) AS project_type,
        COALESCE(l.organization_id, r.organization_id) AS organization_id,
        COALESCE(l.projectname, r.projectname) AS projectname,
        COALESCE(l.project_id, r.project_id) AS project_id,
        COALESCE(l.labeltaskid, r.labeltaskid) AS labeltaskid,
        l.document_id AS document_id_label,
        r.document_id AS document_id_review,
        l.updatedby AS updatedby_label,
        r.updatedby AS updatedby_review,
        r.updatedat_date AS updatedat_date_review,
        COALESCE(l.page, r.page) AS page,
        l.object_id AS object_id_label,
        r.object_id AS object_id_review,
        CASE 
            WHEN l.object_id IS NOT NULL AND r.object_id IS NOT NULL THEN 'persistent'
            WHEN l.object_id IS NOT NULL AND r.object_id IS NULL THEN 'deleted'
            WHEN l.object_id IS NULL AND r.object_id IS NOT NULL THEN 'added'
        END AS presence_flag
    FROM last_label_submission l
    FULL OUTER JOIN last_review_submission r
        ON l.project_id = r.project_id 
       AND l.labeltaskid = r.labeltaskid 
       AND l.page = r.page 
       AND l.object_id = r.object_id
    WHERE COALESCE(l.labeltaskid, r.labeltaskid) IN (SELECT labeltaskid FROM valid_labeltaskids)
),
task_level AS (
    SELECT
        project_type,
        organization_id,
        projectname,
        project_id,
        labeltaskid,
        SUM(CASE WHEN presence_flag = 'persistent' THEN 1 ELSE 0 END) AS tp,
        SUM(CASE WHEN presence_flag = 'deleted' THEN 1 ELSE 0 END) AS fp,
        SUM(CASE WHEN presence_flag = 'added' THEN 1 ELSE 0 END) AS fn
    FROM label_review_join
    GROUP BY 1, 2, 3, 4, 5
),
task_level_pr AS (
    SELECT
        project_type,
        organization_id,
        projectname,
        project_id,
        labeltaskid,
        ROUND((CAST(tp AS DOUBLE) / NULLIF(tp + fp, 0)), 2) AS precision,
        ROUND((CAST(tp AS DOUBLE) / NULLIF(tp + fn, 0)), 2) AS recall
    FROM task_level
),
task_level_score AS (
    SELECT
        *,
        COALESCE(ROUND((2*precision*recall)/NULLIF(precision+recall, 0), 2), 0) AS f1_score
    FROM task_level_pr
)

-- Base to calculation ends here --
/*
    FN - 6a32bebae79e2fe335e56c86
*/

SELECT *
FROM task_level_score
