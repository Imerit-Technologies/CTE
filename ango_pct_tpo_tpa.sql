WITH 
param AS (
    SELECT organization_id, project_id
    FROM (
        VALUES 
            -- ROW('6a212cd9e77b76403502fa3a', '6a212e91607ae00e04e31b6c')
            ROW('6aabefcae88bf8dba3ac0c1d', '6aabeff4e88bf8dba3ac0c22')
    ) AS t(organization_id, project_id)
),
-- Ratio Calculation starts here --
tsd_raw AS (
    SELECT 
        d.organization_id,
        d.project_id,
        REPLACE(batch, 'BC-', '') AS labeltaskid,
        "detail.val.taskcode" AS document_id,
        email AS updatedby,
        
        CAST(
            COALESCE(
                CAST("detail.val.currentframeactivetime.double" AS DOUBLE),
                CAST("detail.val.currentframeactivetime.int" AS DOUBLE),
                CAST("detail.val.currentframeactivetime" AS DOUBLE)
            ) AS INTEGER
        ) AS currentframeactivetime,
        
        frame,
        action,
        action_phase,
        
        drawable AS object_type,
        -- Normalized Class Values
        LOWER(REPLACE(class, ' ', '_')) AS class,
        identity,

        object_id,
        start,
        time_spent,
        detail
    FROM "curated-datalake-prod".table_ango_pct_time_stat_detail d
    JOIN param p
        ON d.organization_id = p.organization_id
       AND d.project_id = p.project_id
),
tsd_agg AS (
    SELECT 
        organization_id,
        project_id,
        labeltaskid,
        document_id,
        updatedby,
        object_type,
        class,
        COUNT(DISTINCT CONCAT(class, '_', CAST(identity AS VARCHAR))) AS object_count,
        SUM(time_spent) AS timespent,
        COUNT(DISTINCT object_id) AS annotation_count
    FROM tsd_raw
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),
doc_agg_all AS (
    SELECT 
        organization_id, project_id, labeltaskid, document_id, object_type, class,
        SUM(timespent) AS timespent,
        SUM(object_count) AS object_count
    FROM tsd_agg
    GROUP BY 1, 2, 3, 4, 5, 6
),
doc_agg AS (
    SELECT * FROM doc_agg_all WHERE class <> ''
),
tsd_duration AS (
    SELECT organization_id, project_id, labeltaskid, document_id,
        SUM(timespent) / 1000.0 AS duration_sec
    FROM doc_agg_all
    GROUP BY 1, 2, 3, 4
),
class_ratio AS (
    SELECT
        *,
        CAST(timespent AS DOUBLE) / SUM(CAST(timespent AS DOUBLE)) OVER (
            PARTITION BY organization_id, project_id, labeltaskid, document_id
        ) AS class_mf
    FROM doc_agg
),
object_type_ratio AS (
    SELECT
        organization_id, project_id, labeltaskid, document_id, object_type,
        SUM(CAST(timespent AS DOUBLE)) / SUM(SUM(CAST(timespent AS DOUBLE))) OVER (
            PARTITION BY organization_id, project_id, labeltaskid, document_id
        ) AS object_type_mf,
        SUM(object_count) AS object_type_object_count
    FROM doc_agg
    GROUP BY 1, 2, 3, 4, 5
),
class_map AS (
    SELECT 
        organization_id, project_id, labeltaskid, document_id,
        JSON_FORMAT(CAST(MAP_AGG(class, ROUND(class_mf, 2)) AS JSON)) AS class_wise_tpo,
        JSON_FORMAT(CAST(MAP_AGG(class, object_count) AS JSON)) AS class_object_count
    FROM class_ratio
    GROUP BY 1, 2, 3, 4
),
object_type_map AS (
    SELECT 
        organization_id, project_id, labeltaskid, document_id,
        JSON_FORMAT(CAST(MAP_AGG(object_type, ROUND(object_type_mf, 2)) AS JSON)) AS object_type_tpo,
        JSON_FORMAT(CAST(MAP_AGG(object_type, object_type_object_count) AS JSON)) AS object_type_object_count
    FROM object_type_ratio
    GROUP BY 1, 2, 3, 4
),
tsd_final AS (
    SELECT 
        c.organization_id,
        c.project_id,
        c.labeltaskid,
        c.document_id,
        o.object_type_tpo,
        -- o.object_type_object_count,
        c.class_wise_tpo
        -- c.class_object_count,
        -- d.duration_sec
    FROM class_map c
    JOIN object_type_map o
      ON c.organization_id = o.organization_id
     AND c.project_id      = o.project_id
     AND c.labeltaskid     = o.labeltaskid
     AND c.document_id     = o.document_id
    JOIN tsd_duration d
      ON c.organization_id = d.organization_id
     AND c.project_id      = d.project_id
     AND c.labeltaskid     = d.labeltaskid
     AND c.document_id     = d.document_id
),
-- Ration Calculation ends here --
gcl AS (
    SELECT g.document_id, g.stage, g.stage_type, g.stagename
    FROM "curated-datalake-prod".gclogs g
    JOIN param p
        ON g.organization_id = p.organization_id
       AND g.project_id = p.project_id
    GROUP BY 1, 2, 3, 4
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
        a.object_type AS shape,
        a.class,
        a.shape_class_identity,
        a.combo_coordinate
    FROM apt_raw t
    JOIN apa_raw a
        ON t.annotations = a.id
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
apta_agg AS (
    SELECT 
        labeltaskid,
        document_id,
        COUNT(DISTINCT shape) AS total_shapes,
        COUNT(DISTINCT class) AS total_class,
        COUNT(DISTINCT shape_class_identity) AS total_object,
        COUNT(object_id) AS total_annotations
    FROM apta_raw
    GROUP BY 1, 2
),

shape_wise_object_count AS (
    SELECT labeltaskid, document_id, CAST(map_agg(shape, obj_cnt) AS JSON) AS shape_wise_object_count
    FROM (
        SELECT labeltaskid, document_id, shape, COUNT(DISTINCT shape_class_identity) AS obj_cnt
        FROM apta_raw GROUP BY 1, 2, 3
    )
    GROUP BY 1, 2
),
shape_wise_annotation_count AS (
    SELECT labeltaskid, document_id, CAST(map_agg(shape, ann_cnt) AS JSON) AS shape_wise_annotation_count
    FROM (
        SELECT labeltaskid, document_id, shape, COUNT(object_id) AS ann_cnt
        FROM apta_raw GROUP BY 1, 2, 3
    )
    GROUP BY 1, 2
),

class_wise_object_count AS (
    SELECT labeltaskid, document_id, CAST(map_agg(class, obj_cnt) AS JSON) AS class_wise_object_count
    FROM (
        SELECT labeltaskid, document_id, class, COUNT(DISTINCT shape_class_identity) AS obj_cnt
        FROM apta_raw GROUP BY 1, 2, 3
    )
    GROUP BY 1, 2
),
class_wise_annotation_count AS (
    SELECT labeltaskid, document_id, CAST(map_agg(class, ann_cnt) AS JSON) AS class_wise_annotation_count
    FROM (
        SELECT labeltaskid, document_id, class, COUNT(object_id) AS ann_cnt
        FROM apta_raw GROUP BY 1, 2, 3
    )
    GROUP BY 1, 2
),

base AS (
    SELECT 
        t.organization_id,
        t.project_id,
        t.labeltaskid,
        t.document_id,
        t.start_time,
        t.end_time,
        t.updatedby,
        g.stage,
        g.stage_type,
        g.stagename,
        t.duration,
        
        a.total_shapes,
        a.total_class,
        a.total_object,
        a.total_annotations,
        
        so.shape_wise_object_count,
        sa.shape_wise_annotation_count,
        co.class_wise_object_count,
        ca.class_wise_annotation_count
    FROM apt_agg t
    JOIN apta_agg a
    ON t.document_id = a.document_id
    
    JOIN shape_wise_object_count so
    ON t.document_id = so.document_id
    JOIN shape_wise_annotation_count sa
    ON t.document_id = sa.document_id
    
    
    JOIN class_wise_object_count co
    ON t.document_id = co.document_id
    JOIN class_wise_annotation_count ca
    ON t.document_id = ca.document_id
    
    JOIN gcl g
    ON t.document_id = g.document_id
    
),
final AS (
    SELECT 
        b.organization_id,
        b.project_id,
        b.labeltaskid,
        b.document_id,
        b.start_time,
        b.end_time,
        b.updatedby,
        b.stage,
        b.stage_type,
        b.stagename,
        b.duration,
        
        b.total_shapes,
        b.total_class,
        
        b.shape_wise_object_count,
        b.shape_wise_annotation_count,
        
        b.class_wise_object_count,
        b.class_wise_annotation_count,
        
        b.total_object,
        b.total_annotations,
        
        t.object_type_tpo,
        t.class_wise_tpo
    FROM base b
    JOIN tsd_final t ON b.document_id = t.document_id
        
)
SELECT *
FROM final
