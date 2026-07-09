WITH 
param AS (
    SELECT organization_id, project_id
    FROM (
        VALUES 
            ROW('69653d3b2e04320329fd30cb', '6979439fa2a49b048a51e016')   -- Mitre | WF 2
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
        SUM(active_time) AS duration_sec,
        MAX(sequence_num) AS total_frames
    FROM apt_raw
    GROUP BY 1, 2, 3, 4, 5
)
SELECT *
FROM apt_agg
