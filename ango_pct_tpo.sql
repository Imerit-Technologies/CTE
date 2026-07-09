WITH 
param AS (
    SELECT organization_id, project_id
    FROM (
        VALUES 
            ROW('69653d3b2e04320329fd30cb', '6979439fa2a49b048a51e016')   -- Mitre | WF 2
    ) AS t(organization_id, project_id)
),
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
        o.object_type_object_count,
        c.class_wise_tpo,
        c.class_object_count,
        d.duration_sec
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
)
SELECT *
FROM tsd_final
