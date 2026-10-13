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
USE WAREHOUSE COMPUTE_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- PART A: Zero-Copy Cloning
-- ============================================================

-- Snowflake stores data as immutable micro-partitions (columnar,
-- compressed, ~16 MB each). A clone creates a metadata-only copy
-- that SHARES the same physical partitions. It's instant and free
-- until you write to the clone (copy-on-write).
--
-- Louis uses this for pre-production and dev environments.

-- Clone the entire database — instant regardless of size
CREATE OR REPLACE DATABASE BUH_HOL_DEV CLONE BUH_HOL;

-- Prove it's a real copy: query it
SELECT COUNT(*) AS DEV_ENCOUNTERS FROM BUH_HOL_DEV.CORE_DATA.FACT_ENCOUNTER;
SELECT COUNT(*) AS PROD_ENCOUNTERS FROM BUH_HOL.CORE_DATA.FACT_ENCOUNTER;

-- Show that the clone has its own dynamic tables
SHOW DYNAMIC TABLES IN DATABASE BUH_HOL_DEV;

-- Time Travel: query data as it existed in the past
-- (works on both the original and the clone)
SELECT COUNT(*) FROM BUH_HOL.INBOUND.PATIENT AT(OFFSET => -60);
-- ^ Returns the row count from 60 seconds ago

-- Clean up the clone
DROP DATABASE BUH_HOL_DEV;

-- Switch back to main database
USE DATABASE BUH_HOL;


-- ============================================================
-- PART B: Resource Monitors & Warehouse Isolation
-- ============================================================

-- Resource monitors track credit consumption and can notify or
-- suspend a warehouse when it hits a threshold. This prevents
-- runaway queries from burning through your credit allocation.

CREATE OR REPLACE RESOURCE MONITOR BUH_LAB_MONITOR
    WITH CREDIT_QUOTA = 10
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75 PERCENT DO NOTIFY
        ON 90 PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND;

-- Attach to our warehouse
ALTER WAREHOUSE COMPUTE_WH SET RESOURCE_MONITOR = BUH_LAB_MONITOR;

-- View the monitor
SHOW RESOURCE MONITORS;

-- Warehouse isolation: each warehouse is independent compute.
-- Unlike a shared PBI capacity pool, one heavy ETL job can't
-- starve your BI queries — they run on separate warehouses.
--
-- In production you'd have dedicated warehouses:
--   ETL_WH       — for your extraction tools loads
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
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION())
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

-- Classification: predict encounter type from charges and LOS
-- (using Cortex COMPLETE to demonstrate the AI capability)
SELECT
    e.ENCOUNTER_ID,
    e.PATIENT_NAME,
    e.PRIMARY_DIAGNOSIS,
    e.ED_HOURS,
    e.TOTAL_CHARGES,
    SNOWFLAKE.CORTEX.COMPLETE(
        'llama3.1-8b',
        'Given this ED visit: diagnosis=' || COALESCE(e.PRIMARY_DIAGNOSIS, 'unknown')
        || ', hours in ED=' || COALESCE(e.ED_HOURS::VARCHAR, 'N/A')
        || ', charges=$' || COALESCE(e.TOTAL_CHARGES::VARCHAR, 'N/A')
        || '. In one sentence, classify the severity (low/moderate/high/critical) and explain why.'
    ) AS AI_SEVERITY_ASSESSMENT
FROM BUH_HOL.DATAMARTS.ED_THROUGHPUT e
WHERE e.PRIMARY_DIAGNOSIS IS NOT NULL
LIMIT 5;

-- Snowflake ML also supports:
--   SNOWFLAKE.ML.FORECAST() — time series forecasting
--   SNOWFLAKE.ML.ANOMALY_DETECTION() — detect outliers
--   SNOWFLAKE.ML.CLASSIFICATION() — train/predict classifiers
--   SNOWFLAKE.ML.REGRESSION() — train/predict regression models
-- These build, train, and serve models entirely within Snowflake.
