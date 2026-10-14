/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 03: Platform Features

  GOAL: Demonstrate key Snowflake platform capabilities that complement
        the dynamic table pipeline: zero-copy cloning, resource monitors,
        query caching, custom UDFs, and ML functions.

  TIME: ~20 minutes
  PREREQUISITE: Run 01_setup.sql and 02_dynamic_tables.sql first
=============================================================================*/

USE DATABASE BUH_HOL;
USE WAREHOUSE BUH_ANALYTICS_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- PART A: Zero-Copy Cloning + Time Travel Recovery
-- ============================================================

-- Snowflake stores data as immutable micro-partitions (columnar,
-- compressed, ~16 MB each). A clone creates a metadata-only copy
-- that SHARES the same physical partitions. It's instant and free
-- until you write to the clone (copy-on-write).

-- ---- Step 1: Clone the INBOUND schema (instant, regardless of size) ----

CREATE OR REPLACE SCHEMA BUH_HOL.INBOUND_DEV CLONE BUH_HOL.INBOUND;

-- Prove it's a real, independent copy
SELECT 'PROD' AS ENV, COUNT(*) AS PATIENTS FROM BUH_HOL.INBOUND.PATIENT
UNION ALL
SELECT 'DEV',        COUNT(*)              FROM BUH_HOL.INBOUND_DEV.PATIENT;


-- ---- Step 2: Simulate an accident in the dev environment ----

-- A developer meant to run: DELETE FROM PATIENT WHERE PAT_ID = 'P100099'
-- But forgot the WHERE clause...
DELETE FROM BUH_HOL.INBOUND_DEV.PATIENT;

-- Capture the query ID of the bad DELETE — we will use this for recovery
SET bad_query_id = LAST_QUERY_ID();
SELECT $bad_query_id AS ACCIDENTAL_DELETE_QUERY_ID;

-- Check the damage
SELECT 'PROD' AS ENV, COUNT(*) AS PATIENTS FROM BUH_HOL.INBOUND.PATIENT
UNION ALL
SELECT 'DEV',        COUNT(*)              FROM BUH_HOL.INBOUND_DEV.PATIENT;
-- DEV shows 0 patients. Production is untouched (clone isolation).


-- ---- Step 3: Time travel — see what existed before the mistake ----

-- Time travel using the query ID: go back to the moment BEFORE that DELETE ran.
-- This is more reliable than OFFSET (which depends on elapsed seconds).
SELECT COUNT(*) AS PATIENTS_BEFORE_DELETE
FROM BUH_HOL.INBOUND_DEV.PATIENT BEFORE(STATEMENT => $bad_query_id);

-- Preview the lost data
SELECT PAT_ID, PAT_FIRST_NAME, PAT_LAST_NAME
FROM BUH_HOL.INBOUND_DEV.PATIENT BEFORE(STATEMENT => $bad_query_id)
LIMIT 10;

-- Alternative: time travel by offset (useful when you don't have the query ID)
-- SELECT COUNT(*) FROM BUH_HOL_DEV.INBOUND.PATIENT AT(OFFSET => -60);


-- ---- Step 4: Recover — restore the data from time travel ----

-- Use the query ID to recover exactly to the moment before the bad statement
INSERT INTO BUH_HOL.INBOUND_DEV.PATIENT
SELECT * FROM BUH_HOL.INBOUND_DEV.PATIENT BEFORE(STATEMENT => $bad_query_id);

-- Verify full recovery
SELECT 'PROD' AS ENV, COUNT(*) AS PATIENTS FROM BUH_HOL.INBOUND.PATIENT
UNION ALL
SELECT 'DEV',        COUNT(*)              FROM BUH_HOL.INBOUND_DEV.PATIENT;
-- Both show 100+ patients again.


-- ---- Step 5: Clean up ----
DROP SCHEMA BUH_HOL.INBOUND_DEV;


-- ============================================================
-- PART B: Resource Monitors & Warehouse Isolation
-- ============================================================

-- Resource monitors track credit consumption and can notify or
-- suspend a warehouse when it hits a threshold. This prevents
-- runaway queries from consuming more credits than expected.

CREATE OR REPLACE RESOURCE MONITOR BUH_LAB_MONITOR
    WITH CREDIT_QUOTA = 10
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75 PERCENT DO NOTIFY
        ON 90 PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND;

-- Attach to our warehouse
ALTER WAREHOUSE BUH_ANALYTICS_WH SET RESOURCE_MONITOR = BUH_LAB_MONITOR;

-- View the monitor
SHOW RESOURCE MONITORS;

-- Warehouse isolation: each warehouse is independent compute.
-- Unlike a shared capacity pool, one heavy ETL job cannot
-- impact BI query performance — they run on separate warehouses.
--
-- In production, dedicated warehouses provide workload isolation:
--   ETL_WH       — for extraction and loading
--   ANALYTICS_WH — for Power BI / Streamlit reads
--   DEV_WH       — for developer ad-hoc queries


-- ============================================================
-- PART C: Query Caching
-- ============================================================

-- Snowflake has three cache layers:
--   1. RESULT CACHE: exact same query → instant (24h, free, no warehouse)
--   2. LOCAL DISK CACHE: warehouse SSD caches partitions (active while running)
--   3. REMOTE DISK CACHE: shared storage layer cache
--
-- Result cache is especially important for Power BI:
-- when 50 users open the same dashboard, only the first query runs.

-- Run a query
SELECT DEPARTMENT_NAME, ENCOUNTER_COUNT, TOTAL_CHARGES
FROM BUH_HOL.DATAMARTS.DEPARTMENT_DASHBOARD
ORDER BY TOTAL_CHARGES DESC;

-- Run it again — instant (result cache hit)
SELECT DEPARTMENT_NAME, ENCOUNTER_COUNT, TOTAL_CHARGES
FROM BUH_HOL.DATAMARTS.DEPARTMENT_DASHBOARD
ORDER BY TOTAL_CHARGES DESC;

-- Prove it: check query history for cache hit
SELECT QUERY_ID, QUERY_TEXT, BYTES_SCANNED, WAREHOUSE_NAME,
       EXECUTION_STATUS, TOTAL_ELAPSED_TIME
FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION())
WHERE QUERY_TEXT ILIKE '%DEPARTMENT_DASHBOARD%ORDER BY TOTAL_CHARGES%'
ORDER BY START_TIME DESC
LIMIT 2;
-- Second query shows BYTES_SCANNED = 0 and no warehouse used


-- ============================================================
-- PART D: Custom Python UDFs
-- ============================================================

-- You can write Python, Java, JavaScript, or Scala functions
-- that run inside Snowflake's secure sandbox. No data leaves.

-- Clinical example: compute a simple acuity score from encounter data
CREATE OR REPLACE FUNCTION BUH_HOL.CORE_DATA.CLINICAL_ACUITY_SCORE(
    encounter_type VARCHAR,
    los_hours FLOAT,
    total_charges FLOAT
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'score'
AS $$
def score(encounter_type, los_hours, total_charges):
    points = 0
    if encounter_type == 'Inpatient':
        points += 3
    elif encounter_type == 'Emergency':
        points += 2
    elif encounter_type == 'Observation':
        points += 1

    if los_hours is not None:
        if los_hours > 120:    # 5+ days
            points += 3
        elif los_hours > 48:   # 2+ days
            points += 2
        elif los_hours > 12:
            points += 1

    if total_charges is not None:
        if total_charges > 50000:
            points += 3
        elif total_charges > 20000:
            points += 2
        elif total_charges > 5000:
            points += 1

    if points >= 7:
        return 'CRITICAL'
    elif points >= 5:
        return 'HIGH'
    elif points >= 3:
        return 'MODERATE'
    else:
        return 'LOW'
$$;

-- Use it in a query
SELECT
    ENCOUNTER_ID,
    ENCOUNTER_TYPE,
    DEPARTMENT_NAME,
    LOS_DAYS_OR_HOURS,
    TOTAL_CHARGES,
    BUH_HOL.CORE_DATA.CLINICAL_ACUITY_SCORE(ENCOUNTER_TYPE, LOS_DAYS_OR_HOURS, TOTAL_CHARGES) AS ACUITY
FROM BUH_HOL.CORE_DATA.FACT_ENCOUNTER
WHERE ENCOUNTER_TYPE IN ('Inpatient', 'Emergency')
ORDER BY TOTAL_CHARGES DESC
LIMIT 20;


-- ============================================================
-- PART E: ML Functions
-- ============================================================

-- Snowflake Cortex ML functions run models directly in SQL.
-- No infrastructure, no Python notebooks, no model deployment.

-- Use Cortex COMPLETE to generate AI visit summaries from ED data
SELECT
    e.ENCOUNTER_ID,
    e.PATIENT_NAME,
    e.PRIMARY_DIAGNOSIS,
    e.ED_HOURS,
    e.TOTAL_CHARGES,
    SNOWFLAKE.CORTEX.COMPLETE(
        'llama3.1-70b',
        'You are a healthcare data analyst. Summarize this ED visit record in one sentence, '
        || 'noting the diagnosis, time spent, and relative cost level: '
        || 'diagnosis=' || COALESCE(e.PRIMARY_DIAGNOSIS, 'unknown')
        || ', hours_in_ed=' || COALESCE(e.ED_HOURS::VARCHAR, 'N/A')
        || ', total_charges=$' || COALESCE(e.TOTAL_CHARGES::VARCHAR, 'N/A')
    ) AS AI_VISIT_SUMMARY
FROM BUH_HOL.DATAMARTS.ED_THROUGHPUT e
WHERE e.PRIMARY_DIAGNOSIS IS NOT NULL
LIMIT 5;

-- Snowflake ML also supports:
--   SNOWFLAKE.ML.FORECAST() — time series forecasting
--   SNOWFLAKE.ML.ANOMALY_DETECTION() — detect outliers
--   SNOWFLAKE.ML.CLASSIFICATION() — train/predict classifiers
--   SNOWFLAKE.ML.REGRESSION() — train/predict regression models
-- These build, train, and serve models entirely within Snowflake.
