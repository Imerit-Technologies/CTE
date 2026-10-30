WITH raw AS (
    SELECT
        t.organization_id,
        t.project_id,
        t.batch_code,
        t.task_code,
        t.timestamp,
        CAST(t.sequence_num AS INTEGER) AS sequence_num,
        a.object_type,
        a.class,
        a.identity
    FROM table_ango_pct_task t
    JOIN table_ango_pct_annotations a
        ON t.annotations = a.id
       AND a.organization_id = t.organization_id
       AND a.project_id = t.project_id
    WHERE t.organization_id = '69653d3b2e04320329fd30cb'
      AND t.project_id = '6979439fa2a49b048a51e016'
      AND t.batch_code = 'BC-6a3451e330623600017d8ee4'
),
base AS (
    SELECT
        organization_id,
        project_id,
        batch_code,
        task_code,
        COUNT(DISTINCT CONCAT(object_type, '_', class, '_', CAST(identity AS VARCHAR))) AS total_objects,
        COUNT(CONCAT(object_type, '_', class, '_', CAST(identity AS VARCHAR))) AS total_annotations,
        ROW_NUMBER() OVER (PARTITION BY project_id, batch_code ORDER BY MAX(timestamp), task_code) AS stage_flow
    FROM raw
    GROUP BY 1, 2, 3, 4
)
SELECT *
FROM base
ORDER BY stage_flow
