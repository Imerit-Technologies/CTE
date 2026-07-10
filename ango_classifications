WITH
param AS (
    SELECT organization_id, project_id
    FROM (
        VALUES 
            ROW('6995f6b1023dc0023c72fb26', '6a22e6ba565599c366d81af8'),   -- Yuka | Production Food
            ROW('6995f6b1023dc0023c72fb26', '6a22de34565599c366d81af3')   -- Yuka | Production Cosmetics
    ) AS t(organization_id, project_id)
),
classification_raw AS (
    SELECT 
        c.organization_id,
        c.project_id,
        c.labeltaskid,
        c.document_id,
        c.objectid,
        c.title,
        c.answer,
        c.tool,
        c.updatedby,
        FROM_UNIXTIME(c.updatedat + 19500) AS updatedat_date_ist
    FROM "curated-datalake-prod".classifications c
    JOIN param p
      ON c.organization_id = p.organization_id
     AND c.project_id = p.project_id
)
SELECT *
FROM classification_raw
