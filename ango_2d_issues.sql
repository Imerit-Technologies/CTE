WITH
param AS (
    SELECT organization_id, project_id
    FROM (
        VALUES
            ROW('69653d3b2e04320329fd30cb', '697401b14a33e0719d081060'),   -- Mitre | WF 1
            ROW('69653d3b2e04320329fd30cb', '6979439fa2a49b048a51e016'),   -- Mitre | WF 2
            ROW('69653d3b2e04320329fd30cb', '6994ed2f9b711efca4b233a0'),   -- Mitre | WF 3
            ROW('69653d3b2e04320329fd30cb', '69aa51a6d6b0106c46a25dd4'),   -- Mitre | WF 4
            ROW('69653d3b2e04320329fd30cb', '69d95a9cb0c60e2a7ffb979f')    -- Mitre | WF 5
    ) AS t(organization_id, project_id)
),

issues_raw AS (
    SELECT
        organization_id,
        project_id,
        labeltaskid,
        document_id AS issue_id,
        status,
        deleted,
        FROM_UNIXTIME(updatedat + 19500) AS updatedat_date,
        -- keys_arr kept as ARRAY(varchar), reused via contains() below;
        -- avoids array_join -> split round trip re-splitting the same string 12x/row
        array_distinct(
            transform(cast(json_parse(error_code) AS array(json)), x -> json_extract_scalar(x, '$.key'))
        ) AS keys_arr
    FROM "curated-datalake-prod".issues
    WHERE
        organization_id IN (SELECT DISTINCT organization_id FROM param)
        AND project_id IN (SELECT DISTINCT project_id FROM param)
),

-- Project Specific Aggregation --> Every Project has different Error --> hardcoded per project taxonomy
issues_agg AS (
    SELECT
        DATE(updatedat_date) AS updatedat_date,
        organization_id,
        project_id,
        labeltaskid,
        COUNT(DISTINCT issue_id) AS total_issues,
        COUNT(DISTINCT issue_id) FILTER (WHERE status = 'Open') AS open_issues,
        COUNT(DISTINCT issue_id) FILTER (WHERE status = 'Resolved') AS resolved_issues,
        COUNT(DISTINCT issue_id) FILTER (WHERE deleted = true) AS deleted_issues,

        -- Project Specific
        COUNT(DISTINCT CASE WHEN contains(keys_arr, 'Wrong Tool') THEN issue_id END) AS wrong_tool,
        COUNT(DISTINCT CASE WHEN contains(keys_arr, 'Wrong') THEN issue_id END) AS wrong,
        COUNT(DISTINCT CASE WHEN contains(keys_arr, 'TMP-01 | Timestamp Outside Window') THEN issue_id END) AS tmp_01,
        COUNT(DISTINCT CASE WHEN contains(keys_arr, 'TAG-01 | Missing or Wrong Tag') THEN issue_id END) AS tag_01,
        COUNT(DISTINCT CASE WHEN contains(keys_arr, 'REC-01 | Missed Event') THEN issue_id END) AS rec_01,
        COUNT(DISTINCT CASE WHEN contains(keys_arr, 'PRE-01 | False Positive') THEN issue_id END) AS pre_01,
        COUNT(DISTINCT CASE WHEN contains(keys_arr, 'QA-001') THEN issue_id END) AS qa_001,
        COUNT(DISTINCT CASE WHEN contains(keys_arr, 'Missing/Wrong Attribute') THEN issue_id END) AS missing_wrong_attribute,
        COUNT(DISTINCT CASE WHEN contains(keys_arr, 'Missing') THEN issue_id END) AS missing,
        COUNT(DISTINCT CASE WHEN contains(keys_arr, 'Missing Tool') THEN issue_id END) AS missing_tool,
        COUNT(DISTINCT CASE WHEN contains(keys_arr, 'CLS-01 | Wrong Class') THEN issue_id END) AS cls_01,
        COUNT(DISTINCT CASE WHEN contains(keys_arr, 'ATR-03 | Wrong Soil Humidity') THEN issue_id END) AS atr_03,
        COUNT(DISTINCT CASE WHEN contains(keys_arr, 'ATR-01 | Wrong Soil Type') THEN issue_id END) AS atr_01

    FROM issues_raw
    GROUP BY 1, 2, 3, 4
    ORDER BY 1 DESC
)
SELECT *
FROM issues_agg
