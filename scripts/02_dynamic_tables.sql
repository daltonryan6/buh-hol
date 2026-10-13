/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 02: Dynamic Tables

  GOAL: Build a multi-layer pipeline using dynamic tables that
        automatically refresh when source data changes. This replaces
        the existing scheduled transformations with declarative SQL.

  ARCHITECTURE:
    INBOUND (Clarity extracts) --> CORE_DATA (dimensional model) --> DATAMARTS (reporting)

  TIME: ~40 minutes
  PREREQUISITE: Run 01_setup.sql first
=============================================================================*/

USE DATABASE BUH_HOL;
USE WAREHOUSE COMPUTE_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- PART A: The problem - manual pipelines
-- ============================================================

-- Today, your team runs a series of scheduled SQL transformations:
--   1. Read from INBOUND (raw Clarity extracts)
--   2. Clean, join, and model into curated tables
--   3. Aggregate into gold reporting tables
--   4. Log success/failure, handle retries
--
-- Each step is a script you schedule, monitor, and fix when it breaks.
--
-- Dynamic tables flip this: you declare WHAT the result should
-- look like, and Snowflake figures out WHEN to refresh it.
-- No cron jobs. No orchestration. No manual MERGE scripts.

-- ============================================================
-- PART B: Build the CORE_DATA layer (dimensional model)
-- ============================================================
-- These dynamic tables transform messy Clarity source data into
-- a clean star schema. Each one reads from INBOUND and applies
-- business logic that your existing ETL handles today.

-- DIM_PATIENT: Clean demographics from Clarity PATIENT table
-- Note: Clarity stores names in mixed case, phones without formatting
-- AGE is computed against a fixed reporting-period date ('2025-01-01'),
-- NOT CURRENT_DATE(). Non-deterministic functions like CURRENT_DATE()
-- prevent incremental refresh — a common gotcha with dynamic tables.
-- REFRESH_MODE = INCREMENTAL: simple projection, perfect for change-only processing
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.CORE_DATA.DIM_PATIENT
  TARGET_LAG = '1 minute'
  REFRESH_MODE = INCREMENTAL
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    PAT_ID,
    PAT_MRN_ID,
    INITCAP(PAT_FIRST_NAME)  AS FIRST_NAME,
    INITCAP(PAT_LAST_NAME)   AS LAST_NAME,
    BIRTH_DATE,
    DATEDIFF('year', BIRTH_DATE, '2025-01-01'::DATE) AS AGE,
    SSN,
    ADD_LINE_1               AS ADDRESS,
    CITY,
    STATE_ABBR               AS STATE,
    ZIP,
    SUBSTR(HOME_PHONE,1,3) || '-' || SUBSTR(HOME_PHONE,4,3) || '-' || SUBSTR(HOME_PHONE,7,4) AS PHONE,
    EMAIL_ADDRESS            AS EMAIL,
    LANGUAGE,
    SEX                      AS GENDER,
    LOAD_TS                  AS SOURCE_LOADED_AT
FROM BUH_HOL.INBOUND.PATIENT;

-- DIM_PROVIDER: Clean provider dimension from CLARITY_SER
-- REFRESH_MODE = INCREMENTAL: filter + projection, low complexity
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.CORE_DATA.DIM_PROVIDER
  TARGET_LAG = '1 minute'
  REFRESH_MODE = INCREMENTAL
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    PROV_ID,
    PROV_NAME,
    SPECIALTY,
    DEPARTMENT,
    NPI,
    CASE WHEN ACTIVE_STATUS = 'Y' THEN TRUE ELSE FALSE END AS IS_ACTIVE
FROM BUH_HOL.INBOUND.CLARITY_SER
WHERE ACTIVE_STATUS = 'Y';

-- FACT_ENCOUNTER: Join PAT_ENC with CLARITY_SER, decode type codes,
-- compute length of stay. This is the core clinical fact table.
-- REFRESH_MODE = ADAPTIVE: handles extraction tools bulk loads gracefully by
-- auto-reinitializing when a full table reload lands, then resuming
-- incremental processing for normal row-by-row changes.
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.CORE_DATA.FACT_ENCOUNTER
  TARGET_LAG = '1 minute'
  REFRESH_MODE = ADAPTIVE
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    e.PAT_ENC_CSN_ID         AS ENCOUNTER_ID,
    e.PAT_ID,
    CASE e.ENC_TYPE_C
        WHEN 1 THEN 'Inpatient'
        WHEN 2 THEN 'Outpatient'
        WHEN 3 THEN 'Emergency'
        WHEN 4 THEN 'Observation'
        ELSE 'Unknown'
    END                      AS ENCOUNTER_TYPE,
    e.CONTACT_DATE,
    e.HOSP_ADMSN_TIME        AS ADMIT_TIME,
    e.HOSP_DISCH_TIME        AS DISCHARGE_TIME,
    CASE
        WHEN e.ENC_TYPE_C IN (1,4) AND e.HOSP_DISCH_TIME IS NOT NULL
        THEN DATEDIFF('day', e.HOSP_ADMSN_TIME, e.HOSP_DISCH_TIME)
        WHEN e.ENC_TYPE_C = 3 AND e.HOSP_DISCH_TIME IS NOT NULL
        THEN ROUND(DATEDIFF('minute', e.HOSP_ADMSN_TIME, e.HOSP_DISCH_TIME) / 60.0, 1)
        ELSE NULL
    END                      AS LOS_DAYS_OR_HOURS,
    e.DEPARTMENT_NAME,
    e.VISIT_PROV_ID,
    s.PROV_NAME              AS PROVIDER_NAME,
    s.SPECIALTY              AS PROVIDER_SPECIALTY,
    e.ACCT_BASECLS_HA        AS TOTAL_CHARGES,
    CASE WHEN e.ENC_CLOSED_YN = 'Y' THEN TRUE ELSE FALSE END AS IS_CLOSED,
    e.LOAD_TS                AS SOURCE_LOADED_AT
FROM BUH_HOL.INBOUND.PAT_ENC e
LEFT JOIN BUH_HOL.INBOUND.CLARITY_SER s ON e.VISIT_PROV_ID = s.PROV_ID;

-- FACT_DIAGNOSIS: Join diagnosis list to encounters for context
-- REFRESH_MODE = INCREMENTAL: straightforward join, small change volumes
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.CORE_DATA.FACT_DIAGNOSIS
  TARGET_LAG = '1 minute'
  REFRESH_MODE = INCREMENTAL
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    d.PAT_ENC_CSN_ID         AS ENCOUNTER_ID,
    e.PAT_ID,
    d.LINE                   AS DX_SEQUENCE,
    d.ICD10_CODE,
    d.DX_NAME,
    CASE WHEN d.LINE = 1 THEN TRUE ELSE FALSE END AS IS_PRIMARY,
    e.CONTACT_DATE,
    e.DEPARTMENT_NAME
FROM BUH_HOL.INBOUND.HSP_ACCT_DX_LIST d
JOIN BUH_HOL.INBOUND.PAT_ENC e ON d.PAT_ENC_CSN_ID = e.PAT_ENC_CSN_ID;

-- FACT_ORDER: Lab results with abnormal flagging
-- REFRESH_MODE = INCREMENTAL: join + CASE decode, well-suited for incremental
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.CORE_DATA.FACT_ORDER
  TARGET_LAG = '1 minute'
  REFRESH_MODE = INCREMENTAL
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    o.ORDER_PROC_ID,
    o.PAT_ENC_CSN_ID         AS ENCOUNTER_ID,
    o.PAT_ID,
    o.PROC_CODE,
    o.DESCRIPTION             AS ORDER_NAME,
    o.ORD_VALUE               AS RESULT_VALUE,
    o.RESULT_UNIT,
    o.REFERENCE_LOW,
    o.REFERENCE_HIGH,
    CASE o.RESULT_FLAG_C
        WHEN 0 THEN 'Normal'
        WHEN 1 THEN 'High'
        WHEN 2 THEN 'Low'
        ELSE 'Unknown'
    END                       AS RESULT_FLAG,
    o.RESULT_DATE,
    e.DEPARTMENT_NAME
FROM BUH_HOL.INBOUND.ORDER_PROC o
LEFT JOIN BUH_HOL.INBOUND.PAT_ENC e ON o.PAT_ENC_CSN_ID = e.PAT_ENC_CSN_ID;


-- ============================================================
-- PART C: Build the DATAMARTS layer (reporting aggregates)
-- ============================================================
-- DATAMARTS reads from CORE_DATA (which reads INBOUND). The whole
-- graph refreshes automatically when source data changes.

-- DEPARTMENT_DASHBOARD: Operational metrics by department
-- Joins THREE source systems: Clarity encounters, Strata budgets, Workday purchases
-- This is the key multi-source consolidation table in the pipeline.
-- TARGET_LAG = 15 minutes: operational reporting doesn't need sub-minute freshness
-- REFRESH_MODE = FULL: aggregation over the full dataset, predictable cost per refresh
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.DATAMARTS.DEPARTMENT_DASHBOARD
  TARGET_LAG = '15 minutes'
  REFRESH_MODE = FULL
  WAREHOUSE = COMPUTE_WH
AS
WITH encounter_stats AS (
    SELECT
        DEPARTMENT_NAME,
        COUNT(DISTINCT ENCOUNTER_ID)              AS ENCOUNTER_COUNT,
        COUNT(DISTINCT PAT_ID)                    AS UNIQUE_PATIENTS,
        COUNT_IF(ENCOUNTER_TYPE = 'Inpatient')    AS INPATIENT_COUNT,
        COUNT_IF(ENCOUNTER_TYPE = 'Emergency')    AS ED_COUNT,
        COUNT_IF(ENCOUNTER_TYPE = 'Outpatient')   AS OUTPATIENT_COUNT,
        ROUND(AVG(CASE WHEN ENCOUNTER_TYPE = 'Inpatient'
                  THEN LOS_DAYS_OR_HOURS END), 1) AS AVG_INPATIENT_LOS_DAYS,
        SUM(TOTAL_CHARGES)                        AS TOTAL_CHARGES,
        ROUND(AVG(TOTAL_CHARGES), 2)              AS AVG_CHARGE_PER_ENCOUNTER
    FROM BUH_HOL.CORE_DATA.FACT_ENCOUNTER
    GROUP BY DEPARTMENT_NAME
),
budget_stats AS (
    -- Strata Decision Support: current fiscal year budget by department
    SELECT
        DEPARTMENT_NAME,
        SUM(BUDGET_AMOUNT) AS ANNUAL_BUDGET
    FROM BUH_HOL.INBOUND.STRATA_BUDGET
    WHERE FISCAL_YEAR = 2024
    GROUP BY DEPARTMENT_NAME
),
purchase_stats AS (
    -- Workday Procurement: current year purchasing by department
    SELECT
        DEPARTMENT_NAME,
        COUNT(*)           AS PURCHASE_ORDER_COUNT,
        SUM(PO_AMOUNT)    AS TOTAL_PURCHASES,
        ROUND(AVG(PO_AMOUNT), 2) AS AVG_PO_AMOUNT
    FROM BUH_HOL.INBOUND.WORKDAY_PURCHASES
    WHERE YEAR(PO_DATE) = 2024
    GROUP BY DEPARTMENT_NAME
)
SELECT
    e.DEPARTMENT_NAME,
    -- Clarity: encounter metrics
    e.ENCOUNTER_COUNT,
    e.UNIQUE_PATIENTS,
    e.INPATIENT_COUNT,
    e.ED_COUNT,
    e.OUTPATIENT_COUNT,
    e.AVG_INPATIENT_LOS_DAYS,
    e.TOTAL_CHARGES,
    e.AVG_CHARGE_PER_ENCOUNTER,
    -- Strata: budget vs actual
    b.ANNUAL_BUDGET,
    ROUND(e.TOTAL_CHARGES / NULLIF(b.ANNUAL_BUDGET, 0) * 100, 1) AS PCT_BUDGET_CONSUMED,
    -- Workday: purchasing
    COALESCE(w.PURCHASE_ORDER_COUNT, 0) AS PURCHASE_ORDER_COUNT,
    COALESCE(w.TOTAL_PURCHASES, 0)      AS TOTAL_PURCHASES,
    w.AVG_PO_AMOUNT
FROM encounter_stats e
LEFT JOIN budget_stats b ON e.DEPARTMENT_NAME = b.DEPARTMENT_NAME
LEFT JOIN purchase_stats w ON e.DEPARTMENT_NAME = w.DEPARTMENT_NAME;

-- ED_THROUGHPUT: Emergency Department operations
-- TARGET_LAG = 1 minute: real-time ED dashboard for patient flow
-- REFRESH_MODE = ADAPTIVE: multi-table join; adaptive handles occasional
-- bulk reloads from upstream without manual intervention
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.DATAMARTS.ED_THROUGHPUT
  TARGET_LAG = '1 minute'
  REFRESH_MODE = ADAPTIVE
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    e.ENCOUNTER_ID,
    e.PAT_ID,
    p.FIRST_NAME || ' ' || p.LAST_NAME  AS PATIENT_NAME,
    e.CONTACT_DATE,
    e.ADMIT_TIME,
    e.DISCHARGE_TIME,
    ROUND(DATEDIFF('minute', e.ADMIT_TIME, e.DISCHARGE_TIME) / 60.0, 1) AS ED_HOURS,
    d.ICD10_CODE                         AS PRIMARY_DX_CODE,
    d.DX_NAME                            AS PRIMARY_DIAGNOSIS,
    e.PROVIDER_NAME,
    e.TOTAL_CHARGES
FROM BUH_HOL.CORE_DATA.FACT_ENCOUNTER e
JOIN BUH_HOL.CORE_DATA.DIM_PATIENT p ON e.PAT_ID = p.PAT_ID
LEFT JOIN BUH_HOL.CORE_DATA.FACT_DIAGNOSIS d
    ON e.ENCOUNTER_ID = d.ENCOUNTER_ID AND d.IS_PRIMARY = TRUE
WHERE e.ENCOUNTER_TYPE = 'Emergency';

-- READMISSION_RISK: Patients with 2+ encounters within 30 days
-- TARGET_LAG = DOWNSTREAM: only refreshes when a downstream consumer queries it.
-- Perfect for analytics tables that don't need continuous freshness.
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.DATAMARTS.READMISSION_RISK
  TARGET_LAG = DOWNSTREAM
  REFRESH_MODE = INCREMENTAL
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    e1.PAT_ID,
    p.FIRST_NAME || ' ' || p.LAST_NAME  AS PATIENT_NAME,
    p.AGE,
    e1.ENCOUNTER_ID                      AS INITIAL_ENCOUNTER,
    e1.ENCOUNTER_TYPE                    AS INITIAL_TYPE,
    e1.CONTACT_DATE                      AS INITIAL_DATE,
    e1.DEPARTMENT_NAME                   AS INITIAL_DEPT,
    e2.ENCOUNTER_ID                      AS RETURN_ENCOUNTER,
    e2.ENCOUNTER_TYPE                    AS RETURN_TYPE,
    e2.CONTACT_DATE                      AS RETURN_DATE,
    e2.DEPARTMENT_NAME                   AS RETURN_DEPT,
    DATEDIFF('day', e1.CONTACT_DATE, e2.CONTACT_DATE) AS DAYS_BETWEEN
FROM BUH_HOL.CORE_DATA.FACT_ENCOUNTER e1
JOIN BUH_HOL.CORE_DATA.FACT_ENCOUNTER e2
    ON e1.PAT_ID = e2.PAT_ID
    AND e2.CONTACT_DATE > e1.CONTACT_DATE
    AND DATEDIFF('day', e1.CONTACT_DATE, e2.CONTACT_DATE) <= 30
JOIN BUH_HOL.CORE_DATA.DIM_PATIENT p ON e1.PAT_ID = p.PAT_ID
WHERE e1.ENCOUNTER_TYPE IN ('Inpatient', 'Emergency');


-- ============================================================
-- PART D: Verify the pipeline
-- ============================================================

-- Check CORE_DATA tables are populating
SELECT 'DIM_PATIENT' AS DT, COUNT(*) AS ROWS FROM BUH_HOL.CORE_DATA.DIM_PATIENT
UNION ALL SELECT 'DIM_PROVIDER', COUNT(*) FROM BUH_HOL.CORE_DATA.DIM_PROVIDER
UNION ALL SELECT 'FACT_ENCOUNTER', COUNT(*) FROM BUH_HOL.CORE_DATA.FACT_ENCOUNTER
UNION ALL SELECT 'FACT_DIAGNOSIS', COUNT(*) FROM BUH_HOL.CORE_DATA.FACT_DIAGNOSIS
UNION ALL SELECT 'FACT_ORDER', COUNT(*) FROM BUH_HOL.CORE_DATA.FACT_ORDER
ORDER BY DT;

-- Check DATAMARTS tables
SELECT * FROM BUH_HOL.DATAMARTS.DEPARTMENT_DASHBOARD ORDER BY TOTAL_CHARGES DESC;
SELECT * FROM BUH_HOL.DATAMARTS.ED_THROUGHPUT ORDER BY CONTACT_DATE;
SELECT * FROM BUH_HOL.DATAMARTS.READMISSION_RISK ORDER BY DAYS_BETWEEN;


-- ============================================================
-- PART E: Watch it refresh - the "aha moment"
-- ============================================================

-- A new patient arrives in the ED. In production, your extraction tools
-- would upsert this into INBOUND from Clarity. We simulate it here.

-- New patient
INSERT INTO BUH_HOL.INBOUND.PATIENT
  (PAT_ID,PAT_MRN_ID,PAT_FIRST_NAME,PAT_LAST_NAME,BIRTH_DATE,SSN,
   ADD_LINE_1,CITY,STATE_ABBR,ZIP,HOME_PHONE,EMAIL_ADDRESS,LANGUAGE,SEX)
VALUES
  ('P200001','MRN-900001','jorge','medina','1958-11-20','111-00-2222',
   '650 Elmwood Ave','Providence','RI','02907','4015550116','jmedina@example.com','Spanish','Male');

-- New ED encounter
INSERT INTO BUH_HOL.INBOUND.PAT_ENC
  (PAT_ENC_CSN_ID,PAT_ID,ENC_TYPE_C,CONTACT_DATE,HOSP_ADMSN_TIME,HOSP_DISCH_TIME,
   DEPARTMENT_ID,DEPARTMENT_NAME,VISIT_PROV_ID,ACCT_BASECLS_HA,ENC_CLOSED_YN)
VALUES
  ('E200026','P200001',3,'2024-11-28','2024-11-28 14:30:00','2024-11-28 20:15:00',
   1003,'Emergency Department','PROV-003',5800.00,'Y');

-- Diagnosis for the encounter
INSERT INTO BUH_HOL.INBOUND.HSP_ACCT_DX_LIST VALUES
  ('E200026',1,'DX031','I63.9','Cerebral infarction unspecified');

-- Lab order
INSERT INTO BUH_HOL.INBOUND.ORDER_PROC
  (ORDER_PROC_ID,PAT_ENC_CSN_ID,PAT_ID,PROC_CODE,DESCRIPTION,
   ORD_VALUE,RESULT_UNIT,REFERENCE_LOW,REFERENCE_HIGH,RESULT_FLAG_C,RESULT_DATE)
VALUES
  ('OP029','E200026','P200001','TROP','Troponin I',
   0.15,'ng/mL',0.00,0.04,1,'2024-11-28 15:00:00');

-- *** Wait ~1 minute for dynamic tables to refresh ***

-- Check the CORE_DATA layer - new patient should appear
SELECT * FROM BUH_HOL.CORE_DATA.DIM_PATIENT WHERE PAT_ID = 'P200001';

-- Check DATAMARTS - the ED throughput dashboard should include the new visit
SELECT * FROM BUH_HOL.DATAMARTS.ED_THROUGHPUT WHERE PAT_ID = 'P200001';

-- Check the department dashboard - ED numbers should have increased
SELECT * FROM BUH_HOL.DATAMARTS.DEPARTMENT_DASHBOARD
WHERE DEPARTMENT_NAME = 'Emergency Department';


-- ============================================================
-- PART F: Monitor pipeline health
-- ============================================================

-- Refresh history - see every refresh that has run
SELECT
    NAME,
    STATE,
    STATE_MESSAGE,
    REFRESH_START_TIME,
    REFRESH_END_TIME,
    DATEDIFF('second', REFRESH_START_TIME, REFRESH_END_TIME) AS REFRESH_SECONDS
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
ORDER BY REFRESH_START_TIME DESC
LIMIT 20;

-- Pipeline graph - see all dynamic tables and their status
SELECT
    NAME,
    TARGET_LAG,
    SCHEDULING_STATE
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_GRAPH_HISTORY())
WHERE DATABASE_NAME = 'BUH_HOL'
ORDER BY NAME;


-- ============================================================
-- PART G: Streams + Tasks — event-driven complement
-- ============================================================

-- Dynamic tables are DECLARATIVE: "here is the result I want."
-- Streams + Tasks are IMPERATIVE: "when this changes, do that."
--
-- Use dynamic tables for: transformations, dimensional models, aggregations
-- Use streams + tasks for: audit logging, notifications, triggering
--   external systems, complex CDC patterns with side effects
--
-- Below we create a stream that captures changes to the PATIENT table
-- and a task that logs new patient arrivals into an audit table.

-- Audit log table
CREATE OR REPLACE TABLE BUH_HOL.GOVERNANCE.PATIENT_AUDIT_LOG (
    AUDIT_ID         NUMBER AUTOINCREMENT,
    PAT_ID           VARCHAR(20),
    PAT_MRN_ID       VARCHAR(20),
    PATIENT_NAME     VARCHAR(100),
    ACTION           VARCHAR(10),     -- INSERT, UPDATE, DELETE
    LOGGED_AT        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    LOGGED_BY        VARCHAR(50) DEFAULT CURRENT_USER()
);

-- Stream captures inserts/updates/deletes on INBOUND.PATIENT
CREATE OR REPLACE STREAM BUH_HOL.INBOUND.PATIENT_CHANGES
    ON TABLE BUH_HOL.INBOUND.PATIENT
    SHOW_INITIAL_ROWS = FALSE;

-- Task checks the stream every minute and logs new arrivals
CREATE OR REPLACE TASK BUH_HOL.INBOUND.LOG_PATIENT_CHANGES
    WAREHOUSE = COMPUTE_WH
    SCHEDULE  = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('BUH_HOL.INBOUND.PATIENT_CHANGES')
AS
    INSERT INTO BUH_HOL.GOVERNANCE.PATIENT_AUDIT_LOG (PAT_ID, PAT_MRN_ID, PATIENT_NAME, ACTION)
    SELECT
        PAT_ID,
        PAT_MRN_ID,
        INITCAP(PAT_FIRST_NAME) || ' ' || INITCAP(PAT_LAST_NAME),
        CASE
            WHEN METADATA$ACTION = 'INSERT' AND METADATA$ISUPDATE = FALSE THEN 'INSERT'
            WHEN METADATA$ACTION = 'INSERT' AND METADATA$ISUPDATE = TRUE  THEN 'UPDATE'
            WHEN METADATA$ACTION = 'DELETE' AND METADATA$ISUPDATE = FALSE THEN 'DELETE'
        END
    FROM BUH_HOL.INBOUND.PATIENT_CHANGES;

-- Enable the task (tasks are created in suspended state)
ALTER TASK BUH_HOL.INBOUND.LOG_PATIENT_CHANGES RESUME;

-- Verify the stream and task exist
SHOW STREAMS IN SCHEMA BUH_HOL.INBOUND;
SHOW TASKS IN SCHEMA BUH_HOL.INBOUND;

-- At this point, when you inserted Jorge Medina in Part E, the stream
-- captured that change. The task will pick it up on its next run.
-- Wait ~1 minute, then check the audit log:

SELECT * FROM BUH_HOL.GOVERNANCE.PATIENT_AUDIT_LOG ORDER BY LOGGED_AT DESC;


-- ============================================================
-- PART H: Discussion - design choices in this pipeline
-- ============================================================

-- TARGET_LAG controls freshness, not schedule. Snowflake decides
-- WHEN to refresh. We used three different settings:
--   '1 minute'   = CORE_DATA layer + ED_THROUGHPUT (real-time clinical)
--   '15 minutes' = DEPARTMENT_DASHBOARD (operational, doesn't need sub-minute)
--   DOWNSTREAM   = READMISSION_RISK (analytics — refresh only when queried)
--
-- REFRESH_MODE controls HOW data is refreshed:
--   INCREMENTAL  = process only changed rows (most CORE_DATA tables + READMISSION_RISK)
--   ADAPTIVE     = incremental by default, auto-reinitializes on bulk loads
--                   (FACT_ENCOUNTER, ED_THROUGHPUT — handles extraction tools reloads)
--   FULL         = reprocess everything each refresh (DEPARTMENT_DASHBOARD —
--                   predictable cost for aggregation)
--
-- GOTCHA: Non-deterministic functions (CURRENT_DATE(), CURRENT_TIMESTAMP())
-- force a table to FULL refresh mode. That's why DIM_PATIENT computes AGE
-- against a fixed reporting-period date instead of CURRENT_DATE().
--
-- The combination of TARGET_LAG + REFRESH_MODE gives you fine-grained
-- control over freshness vs. cost. In production, set both explicitly.
--
-- Louis reported: Dynamic Tables used about the same credits as
-- the existing ETL but saved significant engineering time. The
-- value is not in cheaper compute — it is in the orchestration,
-- monitoring, and error-handling code you no longer need to maintain.

-- ============================================================
-- CHECKPOINT
-- ============================================================

-- You should see:
--   - 5 dynamic tables in CORE_DATA (DIM_PATIENT, DIM_PROVIDER,
--     FACT_ENCOUNTER, FACT_DIAGNOSIS, FACT_ORDER)
--   - 3 dynamic tables in DATAMARTS (DEPARTMENT_DASHBOARD,
--     ED_THROUGHPUT, READMISSION_RISK)
--   - New patient P200001 (Jorge Medina) appearing in all layers
--   - ED throughput now includes the new visit
--   - Refresh history showing successful runs
--   - Stream PATIENT_CHANGES and Task LOG_PATIENT_CHANGES active
--   - Audit log captures Jorge Medina's arrival

SELECT 'CORE_DATA.DIM_PATIENT' AS DT, COUNT(*) AS ROWS FROM BUH_HOL.CORE_DATA.DIM_PATIENT
UNION ALL SELECT 'CORE_DATA.DIM_PROVIDER', COUNT(*) FROM BUH_HOL.CORE_DATA.DIM_PROVIDER
UNION ALL SELECT 'CORE_DATA.FACT_ENCOUNTER', COUNT(*) FROM BUH_HOL.CORE_DATA.FACT_ENCOUNTER
UNION ALL SELECT 'CORE_DATA.FACT_DIAGNOSIS', COUNT(*) FROM BUH_HOL.CORE_DATA.FACT_DIAGNOSIS
UNION ALL SELECT 'CORE_DATA.FACT_ORDER', COUNT(*) FROM BUH_HOL.CORE_DATA.FACT_ORDER
UNION ALL SELECT 'DATAMARTS.DEPARTMENT_DASHBOARD', COUNT(*) FROM BUH_HOL.DATAMARTS.DEPARTMENT_DASHBOARD
UNION ALL SELECT 'DATAMARTS.ED_THROUGHPUT', COUNT(*) FROM BUH_HOL.DATAMARTS.ED_THROUGHPUT
UNION ALL SELECT 'DATAMARTS.READMISSION_RISK', COUNT(*) FROM BUH_HOL.DATAMARTS.READMISSION_RISK
ORDER BY DT;
