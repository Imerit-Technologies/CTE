WITH 
param AS (
    SELECT organization_id, project_id
    FROM (
        VALUES             
            ROW('69653d3b2e04320329fd30cb', '697401b14a33e0719d081060'),
            ROW('69653d3b2e04320329fd30cb', '6a6118804588f7956e069851'),
            ROW('69653d3b2e04320329fd30cb', '6a6d2bc171ddd495c10aa987'),
            ROW('69653d3b2e04320329fd30cb', '6a7d5bd0c9f08bebd5768d9d'),
            ROW('69653d3b2e04320329fd30cb', '6a87336c78426b7a1a987e09'),
            ROW('69653d3b2e04320329fd30cb', '6ac71324e6e1acbc2aab4915'),
            ROW('69653d3b2e04320329fd30cb', '6ac032d16cf9e1634ae78066')
    ) AS t(organization_id, project_id)
),
tls AS (
    SELECT project_id, COUNT(DISTINCT labeltaskid) AS tools_task_count
    FROM "curated-datalake-prod".tools
    WHERE organization_id IN (SELECT organization_id FROM param)
      AND project_id IN (SELECT project_id FROM param)
    GROUP BY project_id
),
cls AS (
    SELECT project_id, COUNT(DISTINCT labeltaskid) AS classification_task_count
    FROM "curated-datalake-prod".classifications
    WHERE organization_id IN (SELECT organization_id FROM param)
      AND project_id IN (SELECT project_id FROM param)
    GROUP BY project_id
)
SELECT 
    p.project_id,
    COALESCE(t.tools_task_count, 0) AS tools_task_count,
    COALESCE(c.classification_task_count, 0) AS classification_task_count
FROM param p
LEFT JOIN tls t ON p.project_id = t.project_id
LEFT JOIN cls c ON p.project_id = c.project_id
