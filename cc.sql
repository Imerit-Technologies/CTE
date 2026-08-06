WITH cc AS (
    SELECT
        CAST(se.started_at AS TIMESTAMP) AS started_at,
        CAST(se.ended_at AS TIMESTAMP) AS ended_at,
        se.created_at,
        se.updated_at,
        se.activity,
        se.url,
        tu.email,
        ss.project_id,
        tp.name AS project_name,
        tp.organization_id,
        tg.name AS organization_name
    FROM "imerit-db-datalake-prod".table_sessionentry se 
    JOIN "imerit-db-datalake-prod".table_session ss ON se.session_id = ss.id
    JOIN "imerit-db-datalake-prod".table_project tp ON ss.project_id = tp.id 
    JOIN "imerit-db-datalake-prod".table_organization tg ON tg.id = tp.organization_id
    JOIN "imerit-db-datalake-prod".table_user tu ON tu.id = ss.user_id
    WHERE 
        ss.year = '2026'   
        AND se.year = '2026'
)
SELECT *
FROM cc
