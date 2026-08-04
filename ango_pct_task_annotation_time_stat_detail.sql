WITH 
param AS (
    SELECT organization_id, project_id
    FROM (
        VALUES 
            ROW('69653d3b2e04320329fd30cb', '6979439fa2a49b048a51e016')   -- Bedrock | WF 2
    ) AS t(organization_id, project_id)
),
apt_raw AS (
	SELECT 
        t.organization_id,
        t.project_id,
        REPLACE(batch_code, 'BC-', '') AS labeltaskid,
        task_code AS document_id,
        FROM_UNIXTIME((start_timestamp+19500)/1000) AS start_time,
        FROM_UNIXTIME((timestamp+19500)/1000) AS end_time,
        user,
        active_time,
        CAST(sequence_num AS INTEGER) AS sequence_num,
        annotations
	FROM "curated-datalake-prod".table_ango_pct_task t
	JOIN param p
	    ON t.organization_id = p.organization_id
	   AND t.project_id = p.project_id
),
apt_agg AS (
    SELECT
        organization_id,
        project_id,
        labeltaskid,
        document_id,
        user AS updatedby,
        MIN(start_time) AS start_time,
        MAX(end_time) AS end_time,
        SUM(active_time) AS duration,
        MAX(sequence_num) AS total_frames
    FROM apt_raw
    GROUP BY 1, 2, 3, 4, 5
),
apa_raw AS (
    SELECT 
        a.id,
        a.class,
        CONCAT(a.class, '_', CAST(a.identity AS VARCHAR)) AS class_identity,
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
),
apta_raw AS (
    SELECT 
        t.organization_id,
        t.project_id,
        t.labeltaskid,
        t.document_id,
        t.start_time,
        t.end_time,
        t.user,
        t.active_time,
        t.sequence_num,
        a.object_id,
        a.object_type,
        a.class,
        a.class_identity,
        a.combo_coordinate
    FROM apt_raw t
    JOIN apa_raw a
        ON t.annotations = a.id
),
apta_agg AS (
    SELECT
        t.organization_id,
        t.project_id,
        t.labeltaskid,
        t.document_id,
        t.updatedby,
        t.start_time,
        t.end_time,
        t.duration,
        t.total_frames,
        COUNT(DISTINCT a.object_type) AS total_object_type,
        COUNT(DISTINCT a.class) AS total_class,
        COUNT(DISTINCT a.class_identity) AS total_objects,
        COUNT(DISTINCT a.combo_coordinate) AS total_annotations
    FROM apt_agg t 
    JOIN apta_raw a
    ON t.document_id = a.document_id
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
object_type_agg AS (
    SELECT
        organization_id, project_id, labeltaskid, document_id, user AS updatedby, object_type,
        COUNT(DISTINCT class_identity) AS object_count,
        COUNT(DISTINCT combo_coordinate) AS annotation_count
    FROM apta_raw
    GROUP BY 1, 2, 3, 4, 5, 6
),
object_type_map AS (
    SELECT
        organization_id, project_id, labeltaskid, document_id, updatedby,
        JSON_FORMAT(CAST(MAP_AGG(object_type, object_count) AS JSON)) AS object_type_object_count,
        JSON_FORMAT(CAST(MAP_AGG(object_type, annotation_count) AS JSON)) AS object_type_annotation_count
    FROM object_type_agg
    GROUP BY 1, 2, 3, 4, 5
),
class_agg AS (
    SELECT
        organization_id, project_id, labeltaskid, document_id, user AS updatedby, class,
        COUNT(DISTINCT class_identity) AS object_count,
        COUNT(DISTINCT combo_coordinate) AS annotation_count
    FROM apta_raw
    GROUP BY 1, 2, 3, 4, 5, 6
),
class_map AS (
    SELECT
        organization_id, project_id, labeltaskid, document_id, updatedby,
        JSON_FORMAT(CAST(MAP_AGG(class, object_count) AS JSON)) AS class_object_count,
        JSON_FORMAT(CAST(MAP_AGG(class, annotation_count) AS JSON)) AS class_annotation_count
    FROM class_agg
    GROUP BY 1, 2, 3, 4, 5
),
-- pulled in from time_stat_detail query, just to compute class_wise_tpo
tsd_raw AS (
    SELECT 
        d.organization_id,
        d.project_id,
        REPLACE(batch, 'BC-', '') AS labeltaskid,
        "detail.val.taskcode" AS document_id,
        LOWER(REPLACE(class, ' ', '_')) AS class,
        identity,
        time_spent
    FROM "curated-datalake-prod".table_ango_pct_time_stat_detail d
    JOIN param p
        ON d.organization_id = p.organization_id
       AND d.project_id = p.project_id
),
tsd_agg AS (
    SELECT 
        organization_id, project_id, labeltaskid, document_id, class,
        COUNT(DISTINCT CONCAT(class, '_', CAST(identity AS VARCHAR))) AS object_count,
        SUM(time_spent) AS timespent
    FROM tsd_raw
    WHERE class <> ''
    GROUP BY 1, 2, 3, 4, 5
),
class_ratio AS (
    SELECT
        *,
        CAST(timespent AS DOUBLE) / SUM(CAST(timespent AS DOUBLE)) OVER (
            PARTITION BY organization_id, project_id, labeltaskid, document_id
        ) AS class_mf
    FROM tsd_agg
),
class_wise_tpo_map AS (
    SELECT 
        organization_id, project_id, labeltaskid, document_id,
        JSON_FORMAT(CAST(MAP_AGG(class, ROUND(class_mf, 2)) AS JSON)) AS class_wise_tpo
    FROM class_ratio
    GROUP BY 1, 2, 3, 4
),
final AS (
    SELECT
        g.*,
        o.object_type_object_count,
        o.object_type_annotation_count,
        c.class_object_count,
        c.class_annotation_count,
        w.class_wise_tpo
    FROM apta_agg g
    JOIN object_type_map o
        ON g.organization_id = o.organization_id AND g.project_id = o.project_id
       AND g.labeltaskid = o.labeltaskid AND g.document_id = o.document_id AND g.updatedby = o.updatedby
    JOIN class_map c
        ON g.organization_id = c.organization_id AND g.project_id = c.project_id
       AND g.labeltaskid = c.labeltaskid AND g.document_id = c.document_id AND g.updatedby = c.updatedby
    JOIN class_wise_tpo_map w
        ON g.organization_id = w.organization_id AND g.project_id = w.project_id
       AND g.labeltaskid = w.labeltaskid AND g.document_id = w.document_id
)
SELECT *
FROM final
