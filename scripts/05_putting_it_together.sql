/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 05: Putting It All Together

  GOAL: Verify the end-to-end pipeline and discuss next steps.
  TIME: ~15 minutes
=============================================================================*/

USE DATABASE BUH_HOL;
USE WAREHOUSE COMPUTE_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- Architecture you built today
-- ============================================================

-- [Epic Clarity SQL Server]
--        |
--        | Snowlift / Snowloader (simulated by 00_setup.sql)
--        v
-- INBOUND schema (Clarity table names: PATIENT, PAT_ENC, CLARITY_SER, ORDER_PROC, HSP_ACCT_DX_LIST)
--        |
--        | Dynamic Tables auto-refresh
--        v
-- CURATED schema (dimensional model: DIM_PATIENT, DIM_PROVIDER, FACT_ENCOUNTER, FACT_DIAGNOSIS, FACT_ORDER)
--        |
--        | Dynamic Tables auto-refresh
--        v
-- GOLD schema (reporting: DEPARTMENT_DASHBOARD, ED_THROUGHPUT, READMISSION_RISK)
--        |
--        +--> Snowflake default tables (analytics, AI, sharing)
--        +--> Iceberg tables in OneLake (Power BI Direct Lake)
--
-- GOVERNANCE layer (tags + masking policies) applies across ALL layers
-- Git Workspace provides versioned SQL delivery

-- ============================================================
-- End-to-end verification
-- ============================================================

-- Row counts across all layers
SELECT 'INBOUND.PATIENT' AS LAYER, COUNT(*) AS ROWS FROM BUH_HOL.INBOUND.PATIENT
UNION ALL SELECT 'INBOUND.PAT_ENC', COUNT(*) FROM BUH_HOL.INBOUND.PAT_ENC
UNION ALL SELECT 'INBOUND.ORDER_PROC', COUNT(*) FROM BUH_HOL.INBOUND.ORDER_PROC
UNION ALL SELECT 'CURATED.DIM_PATIENT', COUNT(*) FROM BUH_HOL.CURATED.DIM_PATIENT
UNION ALL SELECT 'CURATED.FACT_ENCOUNTER', COUNT(*) FROM BUH_HOL.CURATED.FACT_ENCOUNTER
UNION ALL SELECT 'CURATED.FACT_ORDER', COUNT(*) FROM BUH_HOL.CURATED.FACT_ORDER
UNION ALL SELECT 'GOLD.DEPARTMENT_DASHBOARD', COUNT(*) FROM BUH_HOL.GOLD.DEPARTMENT_DASHBOARD
UNION ALL SELECT 'GOLD.ED_THROUGHPUT', COUNT(*) FROM BUH_HOL.GOLD.ED_THROUGHPUT
UNION ALL SELECT 'GOLD.READMISSION_RISK', COUNT(*) FROM BUH_HOL.GOLD.READMISSION_RISK
ORDER BY LAYER;

-- Dynamic table pipeline status
SELECT
    NAME,
    TARGET_LAG,
    SCHEDULING_STATE
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_GRAPH_HISTORY())
WHERE DATABASE_NAME = 'BUH_HOL'
ORDER BY NAME;

-- ============================================================
-- Next steps for your environment
-- ============================================================

-- 1. WORKSPACES: Connect your GitLab/GitHub; store all SQL in version control.
--    Replace file-share SQL with Git-backed, reviewable, deployable code.
--
-- 2. DYNAMIC TABLES: Replace Snowforge transformation jobs with declarative SQL.
--    Start with one pipeline (e.g., a department dashboard) and set TARGET_LAG
--    based on business need. Louis noted DTs use similar credits to ETL but
--    save significant engineering time.
--
-- 3. ICEBERG + ONELAKE: Set up an external volume pointing to OneLake.
--    Write only GOLD tables as Iceberg. Connect Power BI via Direct Lake.
--    Size Fabric capacity for BI read load only.
--
-- 4. TAGS + MASKING: Define your PII taxonomy (SSN, MRN, Name, DOB, etc.).
--    Run SYSTEM$CLASSIFY to auto-detect PII across Clarity tables. Attach
--    masking policies to tags so new columns are automatically protected.
--
-- 5. COST MANAGEMENT: Tag warehouses for chargeback by department.
--    Right-size Fabric capacity for BI reads, keep pipeline in Snowflake.
--
-- 6. DEV/TEST/PROD: Use zero-copy cloning for daily prod-to-test refresh.
--    Dynamic tables in the clone auto-refresh against the cloned data.
