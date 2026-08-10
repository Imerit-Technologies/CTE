WITH 
param AS (
    SELECT organization_id, project_id
    FROM (
        VALUES 
            ROW('6a212cd9e77b76403502fa3a', '6a212e91607ae00e04e31b6c')
    ) AS t(organization_id, project_id)
),
gcl AS (
    SELECT g.document_id, g.stage, g.stage_type, g.stagename
    FROM prod."curated-datalake-prod".gclogs g
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
	FROM prod."curated-datalake-prod".table_ango_pct_task t
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
    FROM prod."curated-datalake-prod".table_ango_pct_annotations a
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

tsd_raw AS (
    SELECT 
        d.organization_id,
        d.project_id,
        REPLACE(batch, 'BC-', '') AS labeltaskid,
        "detail.val.taskcode" AS document_id,
        LOWER(REPLACE(class, ' ', '_')) AS class,
        drawable AS shape,
        time_spent
    FROM prod."curated-datalake-prod".table_ango_pct_time_stat_detail d
    JOIN param p
        ON d.organization_id = p.organization_id
       AND d.project_id = p.project_id
    WHERE class <> ''
),
tsd_agg AS (
    SELECT labeltaskid, document_id, shape, class, SUM(time_spent) AS timespent
    FROM tsd_raw
    GROUP BY 1, 2, 3, 4
),
tsd_agg_shape AS (
    SELECT labeltaskid, document_id, shape, SUM(timespent) AS timespent
    FROM tsd_agg
    GROUP BY 1, 2, 3
),
tsd_shape_ratio AS (
    SELECT labeltaskid, document_id,
           CAST(map_agg(shape, ROUND(ratio, 10)) AS JSON) AS shape_wise_ratio
    FROM (
        SELECT labeltaskid, document_id, shape,
               timespent * 1.0 / SUM(timespent) OVER (PARTITION BY labeltaskid, document_id) AS ratio
        FROM tsd_agg_shape
    )
    GROUP BY labeltaskid, document_id
),
tsd_agg_class AS (
    SELECT labeltaskid, document_id, class, SUM(timespent) AS timespent
    FROM tsd_agg
    GROUP BY 1, 2, 3
),
tsd_class_ratio AS (
    SELECT labeltaskid, document_id,
           CAST(map_agg(class, ROUND(ratio, 10)) AS JSON) AS class_wise_ratio
    FROM (
        SELECT labeltaskid, document_id, class,
               timespent * 1.0 / SUM(timespent) OVER (PARTITION BY labeltaskid, document_id) AS ratio
        FROM tsd_agg_class
    )
    GROUP BY labeltaskid, document_id
),
tsd_final AS (
    SELECT 
        c.labeltaskid,
        c.document_id,
        s.shape_wise_ratio,
        c.class_wise_ratio 
    FROM tsd_class_ratio c
    JOIN tsd_shape_ratio s ON c.labeltaskid = s.labeltaskid AND c.document_id = s.document_id
),

final AS (
    SELECT 
        b.*,
        tf.shape_wise_ratio,
        tf.class_wise_ratio
    FROM base b
    JOIN tsd_final tf 
    ON b.document_id = tf.document_id
)

SELECT *
FROM final
