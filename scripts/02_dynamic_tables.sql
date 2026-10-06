/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 02: Dynamic Tables

  GOAL: Build a multi-layer pipeline using dynamic tables that
        automatically refresh when source data changes. This replaces
        the Snowforge-managed transformations with declarative SQL.

  ARCHITECTURE:
    INBOUND (Clarity extracts) --> CURATED (dimensional model) --> GOLD (reporting)

  TIME: ~40 minutes
  PREREQUISITE: Run 00_setup.sql first
=============================================================================*/

USE DATABASE BUH_HOL;
USE WAREHOUSE COMPUTE_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- PART A: The problem - manual pipelines
-- ============================================================

-- Today, Snowforge runs a series of SQL transformations:
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
-- PART B: Build the CURATED layer (dimensional model)
-- ============================================================
-- These dynamic tables transform messy Clarity source data into
-- a clean star schema. Each one reads from INBOUND and applies
-- business logic that Snowforge handles today.

-- DIM_PATIENT: Clean demographics from Clarity PATIENT table
-- Note: Clarity stores names in mixed case, phones without formatting
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.CURATED.DIM_PATIENT
  TARGET_LAG = '1 minute'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    PAT_ID,
    PAT_MRN_ID,
    INITCAP(PAT_FIRST_NAME)  AS FIRST_NAME,
    INITCAP(PAT_LAST_NAME)   AS LAST_NAME,
    BIRTH_DATE,
    DATEDIFF('year', BIRTH_DATE, CURRENT_DATE()) AS AGE,
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
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.CURATED.DIM_PROVIDER
  TARGET_LAG = '1 minute'
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
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.CURATED.FACT_ENCOUNTER
  TARGET_LAG = '1 minute'
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
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.CURATED.FACT_DIAGNOSIS
  TARGET_LAG = '1 minute'
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
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.CURATED.FACT_ORDER
  TARGET_LAG = '1 minute'
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
-- PART C: Build the GOLD layer (reporting aggregates)
-- ============================================================
-- GOLD reads from CURATED (which reads INBOUND). The whole
-- graph refreshes automatically when source data changes.

-- DEPARTMENT_DASHBOARD: Operational metrics by department
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.GOLD.DEPARTMENT_DASHBOARD
  TARGET_LAG = '1 minute'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    e.DEPARTMENT_NAME,
    COUNT(DISTINCT e.ENCOUNTER_ID)              AS ENCOUNTER_COUNT,
    COUNT(DISTINCT e.PAT_ID)                    AS UNIQUE_PATIENTS,
    COUNT_IF(e.ENCOUNTER_TYPE = 'Inpatient')    AS INPATIENT_COUNT,
    COUNT_IF(e.ENCOUNTER_TYPE = 'Emergency')    AS ED_COUNT,
    COUNT_IF(e.ENCOUNTER_TYPE = 'Outpatient')   AS OUTPATIENT_COUNT,
    ROUND(AVG(CASE WHEN e.ENCOUNTER_TYPE = 'Inpatient'
              THEN e.LOS_DAYS_OR_HOURS END), 1) AS AVG_INPATIENT_LOS_DAYS,
    SUM(e.TOTAL_CHARGES)                        AS TOTAL_CHARGES,
    ROUND(AVG(e.TOTAL_CHARGES), 2)              AS AVG_CHARGE_PER_ENCOUNTER
FROM BUH_HOL.CURATED.FACT_ENCOUNTER e
GROUP BY e.DEPARTMENT_NAME;

-- ED_THROUGHPUT: Emergency Department operations
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.GOLD.ED_THROUGHPUT
  TARGET_LAG = '1 minute'
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
FROM BUH_HOL.CURATED.FACT_ENCOUNTER e
JOIN BUH_HOL.CURATED.DIM_PATIENT p ON e.PAT_ID = p.PAT_ID
LEFT JOIN BUH_HOL.CURATED.FACT_DIAGNOSIS d
    ON e.ENCOUNTER_ID = d.ENCOUNTER_ID AND d.IS_PRIMARY = TRUE
WHERE e.ENCOUNTER_TYPE = 'Emergency';

-- READMISSION_RISK: Patients with 2+ encounters within 30 days
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.GOLD.READMISSION_RISK
  TARGET_LAG = '1 minute'
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
FROM BUH_HOL.CURATED.FACT_ENCOUNTER e1
JOIN BUH_HOL.CURATED.FACT_ENCOUNTER e2
    ON e1.PAT_ID = e2.PAT_ID
    AND e2.CONTACT_DATE > e1.CONTACT_DATE
    AND DATEDIFF('day', e1.CONTACT_DATE, e2.CONTACT_DATE) <= 30
JOIN BUH_HOL.CURATED.DIM_PATIENT p ON e1.PAT_ID = p.PAT_ID
WHERE e1.ENCOUNTER_TYPE IN ('Inpatient', 'Emergency');


-- ============================================================
-- PART D: Verify the pipeline
-- ============================================================

-- Check CURATED tables are populating
SELECT 'DIM_PATIENT' AS DT, COUNT(*) AS ROWS FROM BUH_HOL.CURATED.DIM_PATIENT
UNION ALL SELECT 'DIM_PROVIDER', COUNT(*) FROM BUH_HOL.CURATED.DIM_PROVIDER
UNION ALL SELECT 'FACT_ENCOUNTER', COUNT(*) FROM BUH_HOL.CURATED.FACT_ENCOUNTER
UNION ALL SELECT 'FACT_DIAGNOSIS', COUNT(*) FROM BUH_HOL.CURATED.FACT_DIAGNOSIS
UNION ALL SELECT 'FACT_ORDER', COUNT(*) FROM BUH_HOL.CURATED.FACT_ORDER
ORDER BY DT;

-- Check GOLD tables
SELECT * FROM BUH_HOL.GOLD.DEPARTMENT_DASHBOARD ORDER BY TOTAL_CHARGES DESC;
SELECT * FROM BUH_HOL.GOLD.ED_THROUGHPUT ORDER BY CONTACT_DATE;
SELECT * FROM BUH_HOL.GOLD.READMISSION_RISK ORDER BY DAYS_BETWEEN;


-- ============================================================
-- PART E: Watch it refresh - the "aha moment"
-- ============================================================

-- A new patient arrives in the ED. In production, Snowlift/Snowloader
-- would upsert this into INBOUND from Clarity. We simulate it here.

-- New patient
INSERT INTO BUH_HOL.INBOUND.PATIENT
  (PAT_ID,PAT_MRN_ID,PAT_FIRST_NAME,PAT_LAST_NAME,BIRTH_DATE,SSN,
   ADD_LINE_1,CITY,STATE_ABBR,ZIP,HOME_PHONE,EMAIL_ADDRESS,LANGUAGE,SEX)
VALUES
  ('P100016','MRN-900016','jorge','medina','1958-11-20','111-00-2222',
   '650 Elmwood Ave','Providence','RI','02907','4015550116','jmedina@example.com','Spanish','Male');

-- New ED encounter
INSERT INTO BUH_HOL.INBOUND.PAT_ENC
  (PAT_ENC_CSN_ID,PAT_ID,ENC_TYPE_C,CONTACT_DATE,HOSP_ADMSN_TIME,HOSP_DISCH_TIME,
   DEPARTMENT_ID,DEPARTMENT_NAME,VISIT_PROV_ID,ACCT_BASECLS_HA,ENC_CLOSED_YN)
VALUES
  ('E200026','P100016',3,'2024-11-28','2024-11-28 14:30:00','2024-11-28 20:15:00',
   1003,'Emergency Department','PROV-003',5800.00,'Y');

-- Diagnosis for the encounter
INSERT INTO BUH_HOL.INBOUND.HSP_ACCT_DX_LIST VALUES
  ('E200026',1,'DX031','I63.9','Cerebral infarction unspecified');

-- Lab order
INSERT INTO BUH_HOL.INBOUND.ORDER_PROC
  (ORDER_PROC_ID,PAT_ENC_CSN_ID,PAT_ID,PROC_CODE,DESCRIPTION,
   ORD_VALUE,RESULT_UNIT,REFERENCE_LOW,REFERENCE_HIGH,RESULT_FLAG_C,RESULT_DATE)
VALUES
  ('OP029','E200026','P100016','TROP','Troponin I',
   0.15,'ng/mL',0.00,0.04,1,'2024-11-28 15:00:00');

-- *** Wait ~1 minute for dynamic tables to refresh ***

-- Check the CURATED layer - new patient should appear
SELECT * FROM BUH_HOL.CURATED.DIM_PATIENT WHERE PAT_ID = 'P100016';

-- Check GOLD - the ED throughput dashboard should include the new visit
SELECT * FROM BUH_HOL.GOLD.ED_THROUGHPUT WHERE PAT_ID = 'P100016';

-- Check the department dashboard - ED numbers should have increased
SELECT * FROM BUH_HOL.GOLD.DEPARTMENT_DASHBOARD
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
-- PART G: Discussion - TARGET_LAG for your environment
-- ============================================================

-- TARGET_LAG is the key design decision. It controls freshness,
-- not schedule. Snowflake decides WHEN to refresh.
--
-- For BUH, consider:
--   '1 minute'   = ED throughput, real-time clinical dashboards
--   '15 minutes' = operational reporting (department dashboard)
--   '1 hour'     = standard analytics and research queries
--   DOWNSTREAM   = only refresh when a downstream consumer needs it
--
-- Louis reported: Dynamic Tables used about the same credits as
-- the existing ETL but saved significant engineering time. The
-- value is not in cheaper compute - it is in the orchestration,
-- monitoring, and error-handling code you no longer need to maintain.

-- ============================================================
-- CHECKPOINT
-- ============================================================

-- You should see:
--   - 5 dynamic tables in CURATED (DIM_PATIENT, DIM_PROVIDER,
--     FACT_ENCOUNTER, FACT_DIAGNOSIS, FACT_ORDER)
--   - 3 dynamic tables in GOLD (DEPARTMENT_DASHBOARD,
--     ED_THROUGHPUT, READMISSION_RISK)
--   - New patient P100016 (Jorge Medina) appearing in all layers
--   - ED throughput now includes the new visit
--   - Refresh history showing successful runs

SELECT 'CURATED.DIM_PATIENT' AS DT, COUNT(*) AS ROWS FROM BUH_HOL.CURATED.DIM_PATIENT
UNION ALL SELECT 'CURATED.DIM_PROVIDER', COUNT(*) FROM BUH_HOL.CURATED.DIM_PROVIDER
UNION ALL SELECT 'CURATED.FACT_ENCOUNTER', COUNT(*) FROM BUH_HOL.CURATED.FACT_ENCOUNTER
UNION ALL SELECT 'CURATED.FACT_DIAGNOSIS', COUNT(*) FROM BUH_HOL.CURATED.FACT_DIAGNOSIS
UNION ALL SELECT 'CURATED.FACT_ORDER', COUNT(*) FROM BUH_HOL.CURATED.FACT_ORDER
UNION ALL SELECT 'GOLD.DEPARTMENT_DASHBOARD', COUNT(*) FROM BUH_HOL.GOLD.DEPARTMENT_DASHBOARD
UNION ALL SELECT 'GOLD.ED_THROUGHPUT', COUNT(*) FROM BUH_HOL.GOLD.ED_THROUGHPUT
UNION ALL SELECT 'GOLD.READMISSION_RISK', COUNT(*) FROM BUH_HOL.GOLD.READMISSION_RISK
ORDER BY DT;
