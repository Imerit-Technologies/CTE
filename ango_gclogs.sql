WITH 
param AS (
    SELECT organization_id, project_id
    FROM (
        VALUES 
            ROW('69653d3b2e04320329fd30cb', '697401b14a33e0719d081060'),   -- Mitre | WF 1
            ROW('69653d3b2e04320329fd30cb', '6979439fa2a49b048a51e016'),   -- Mitre | WF 2
            ROW('69653d3b2e04320329fd30cb', '6994ed2f9b711efca4b233a0'),   -- Mitre | WF 3
            ROW('69653d3b2e04320329fd30cb', '69aa51a6d6b0106c46a25dd4'),   -- Mitre | WF 4
            ROW('69653d3b2e04320329fd30cb', '69d95a9cb0c60e2a7ffb979f')   -- Mitre | WF 5
    ) AS t(organization_id, project_id)

),
gcl_raw AS (
    SELECT 
        *
    FROM (
        SELECT 
            *,
            ROW_NUMBER() OVER (PARTITION BY labeltaskid, document_id ORDER BY updatedat DESC) AS rn
        FROM "curated-datalake-prod".gclogs
        WHERE 
            organization_id IN (SELECT organization_id FROM param)
            AND project_id IN (SELECT project_id FROM param)
            AND year >= '2025'
    )
    WHERE rn = 1
),
gcl_agg AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY project_id, labeltaskid ORDER BY updatedat_date) AS stage_flow,
        ROW_NUMBER() OVER (PARTITION BY project_id, labeltaskid, stagename ORDER BY updatedat_date) AS node_iteration,
        CASE WHEN (ROW_NUMBER() OVER (PARTITION BY project_id, labeltaskid ORDER BY updatedat_date DESC)) = 1 THEN 'Yes' ELSE 'Other' END is_latest
    FROM (
        SELECT 
            g.organization_id,
            g.project_id,
            pn.projectname,
            json_extract_scalar(batch_details, '$[0].batch_name') AS batch_name,
            g.labeltaskid AS labeltaskid,
            g.document_id,
            
            g.stage,
            CASE WHEN g.stagename IN ('Client Audit', 'Client Bulk Audit') THEN 'Audit' ELSE stagename END AS stagename,
            g.stage_type,
            
            g.rework,
            g.iscompleted,
            g.isskipped,
            
            g.updatedby,
    
            FROM_UNIXTIME(updatedat + 19500) AS updatedat_date,
            
            g.duration/1000.0 AS duration_sec,
            g.idleduration/1000.0 AS idleduration_sec,
            g.blurduration/1000.0 AS blurduration_sec,
            g.number_of_pages
        FROM gcl_raw g
        LEFT JOIN (
            SELECT project_id, max_by(projectname, updatedat) AS projectname
            FROM gcl_raw g
            GROUP BY 1
        ) pn ON g.project_id = pn.project_id
    )
)
SELECT *
FROM gcl_agg
