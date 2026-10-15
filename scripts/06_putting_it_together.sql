/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 06: Putting It All Together

  GOAL: Verify the end-to-end pipeline and discuss next steps.
  TIME: ~15 minutes
  PREREQUISITE: Run scripts 01 through 05 in order
=============================================================================*/

USE DATABASE BUH_HOL;
USE WAREHOUSE BUH_ANALYTICS_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- Architecture you built today
-- ============================================================

-- [Epic Clarity SQL Server]  [Strata]  [Workday]
--        |                      |          |
--        | Extraction tools      | Connectors
--        v                      v          v
-- INBOUND schema (PATIENT, PAT_ENC, CLARITY_SER, ORDER_PROC, HSP_ACCT_DX_LIST, STRATA_BUDGET, WORKDAY_PURCHASES)
--        |
--        | Dynamic Tables auto-refresh
--        v
-- CORE_DATA schema (dimensional model: DIM_PATIENT, DIM_PROVIDER, FACT_ENCOUNTER, FACT_DIAGNOSIS, FACT_ORDER)
--        |
--        | Dynamic Tables auto-refresh
--        v
-- DATAMARTS schema (reporting: DEPARTMENT_DASHBOARD, ED_THROUGHPUT, READMISSION_RISK)
--        |
--        +--> Snowflake default tables (analytics, AI, sharing)
--        +--> Iceberg tables in OneLake (Power BI Direct Lake)
--
-- GOVERNANCE layer (tags + masking policies + row access policies) applies across ALL layers
-- Git Integration provides versioned SQL delivery (connected to GitHub)

-- ============================================================
-- End-to-end verification
-- ============================================================

-- Row counts across all layers
-- You should see rows at every layer. If any count is 0,
-- that layer's dynamic table may still be refreshing — wait
-- a moment and re-run.
SELECT 'INBOUND.PATIENT' AS LAYER, COUNT(*) AS ROW_COUNT FROM BUH_HOL.INBOUND.PATIENT
UNION ALL SELECT 'INBOUND.PAT_ENC', COUNT(*) FROM BUH_HOL.INBOUND.PAT_ENC
UNION ALL SELECT 'INBOUND.ORDER_PROC', COUNT(*) FROM BUH_HOL.INBOUND.ORDER_PROC
UNION ALL SELECT 'INBOUND.STRATA_BUDGET', COUNT(*) FROM BUH_HOL.INBOUND.STRATA_BUDGET
UNION ALL SELECT 'INBOUND.WORKDAY_PURCHASES', COUNT(*) FROM BUH_HOL.INBOUND.WORKDAY_PURCHASES
UNION ALL SELECT 'CORE_DATA.DIM_PATIENT', COUNT(*) FROM BUH_HOL.CORE_DATA.DIM_PATIENT
UNION ALL SELECT 'CORE_DATA.FACT_ENCOUNTER', COUNT(*) FROM BUH_HOL.CORE_DATA.FACT_ENCOUNTER
UNION ALL SELECT 'CORE_DATA.FACT_ORDER', COUNT(*) FROM BUH_HOL.CORE_DATA.FACT_ORDER
UNION ALL SELECT 'DATAMARTS.DEPARTMENT_DASHBOARD', COUNT(*) FROM BUH_HOL.DATAMARTS.DEPARTMENT_DASHBOARD
UNION ALL SELECT 'DATAMARTS.ED_THROUGHPUT', COUNT(*) FROM BUH_HOL.DATAMARTS.ED_THROUGHPUT
UNION ALL SELECT 'DATAMARTS.READMISSION_RISK', COUNT(*) FROM BUH_HOL.DATAMARTS.READMISSION_RISK
ORDER BY LAYER;

-- Quick view of all dynamic tables and their status
SHOW DYNAMIC TABLES IN DATABASE BUH_HOL;

-- ============================================================
-- Next steps for your environment
-- ============================================================

-- 1. WORKSPACES: Connect your GitLab/GitHub; store all SQL in version control.
--    Replace file-share SQL with Git-backed, reviewable, deployable code.
--
-- 2. DYNAMIC TABLES: Replace scheduled transformation jobs with declarative SQL.
--    Start with one pipeline (e.g., a department dashboard) and set TARGET_LAG
--    based on business need. Dynamic tables eliminate orchestration and
--    error-handling overhead. Credit usage depends on the workload: incremental
--    refreshes of append-heavy pipelines can be very efficient, while complex
--    joins may use comparable credits to equivalent scheduled ETL.
--
-- 3. ICEBERG + ONELAKE: Set up an external volume pointing to OneLake.
--    Write only DATAMARTS tables as Iceberg. Connect Power BI via Direct Lake.
--    Size Fabric capacity for BI read load only.
--
-- 4. TAGS + MASKING: Define your PII taxonomy (SSN, MRN, Name, DOB, etc.).
--    Use Snowflake's classification features to auto-detect sensitive data:
--      - SYSTEM$CLASSIFY() for broad semantic classification
--      - Data Classification in Snowsight for PII/PHI auto-detection
--    Attach masking policies to tags so new columns are automatically protected.
--    Review auto-classifications before applying them in production.
--
-- 5. COST MANAGEMENT: Tag warehouses for chargeback by department.
--    Right-size Fabric capacity for BI reads, keep pipeline in Snowflake.
--
-- 6. DEV/TEST/PROD: Use zero-copy cloning for daily prod-to-test refresh.
--    Dynamic tables in the clone auto-refresh against the cloned data,
--    because their FROM clauses resolve within the cloned database.
--
--    CAVEATS:
--    - Cloned dynamic tables refresh independently and consume their own
--      compute credits. Suspend them if the test env doesn't need live refresh.
--    - If a dynamic table references a source in a DIFFERENT database,
--      the clone still points to the original source (not a clone of it).
--    - Clone is a point-in-time snapshot; changes to prod after the clone
--      are not reflected in the cloned environment.
