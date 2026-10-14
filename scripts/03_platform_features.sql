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

-- ---- Step 1: Clone the PATIENT table (instant, regardless of size) ----

CREATE OR REPLACE TABLE BUH_HOL.INBOUND.PATIENT_DEV CLONE BUH_HOL.INBOUND.PATIENT;

-- Prove it's a real, independent copy
SELECT 'PROD' AS ENV, COUNT(*) AS PATIENTS FROM BUH_HOL.INBOUND.PATIENT
UNION ALL
SELECT 'DEV',        COUNT(*)              FROM BUH_HOL.INBOUND.PATIENT_DEV;


-- ---- Step 2: Simulate an accident in the dev copy ----

-- A developer meant to run: DELETE FROM PATIENT_DEV WHERE PAT_ID = 'P100099'
-- But forgot the WHERE clause...
DELETE FROM BUH_HOL.INBOUND.PATIENT_DEV;

-- Capture the query ID of the bad DELETE — we will use this for recovery
SET bad_query_id = LAST_QUERY_ID();
SELECT $bad_query_id AS ACCIDENTAL_DELETE_QUERY_ID;

-- Check the damage
SELECT 'PROD' AS ENV, COUNT(*) AS PATIENTS FROM BUH_HOL.INBOUND.PATIENT
UNION ALL
SELECT 'DEV',        COUNT(*)              FROM BUH_HOL.INBOUND.PATIENT_DEV;
-- DEV shows 0 patients. Production is untouched (clone isolation).


-- ---- Step 3: Time travel — see what existed before the mistake ----

-- Time travel using the query ID: go back to the moment BEFORE that DELETE ran.
-- This is more reliable than OFFSET (which depends on elapsed seconds).
SELECT COUNT(*) AS PATIENTS_BEFORE_DELETE
FROM BUH_HOL.INBOUND.PATIENT_DEV BEFORE(STATEMENT => $bad_query_id);

-- Preview the lost data
SELECT PAT_ID, PAT_FIRST_NAME, PAT_LAST_NAME
FROM BUH_HOL.INBOUND.PATIENT_DEV BEFORE(STATEMENT => $bad_query_id)
LIMIT 10;

-- Alternative: time travel by offset (useful when you don't have the query ID)
-- SELECT COUNT(*) FROM BUH_HOL.INBOUND.PATIENT_DEV AT(OFFSET => -60);


-- ---- Step 4: Recover — restore the data from time travel ----

-- Use the query ID to recover exactly to the moment before the bad statement
INSERT INTO BUH_HOL.INBOUND.PATIENT_DEV
SELECT * FROM BUH_HOL.INBOUND.PATIENT_DEV BEFORE(STATEMENT => $bad_query_id);

-- Verify full recovery
SELECT 'PROD' AS ENV, COUNT(*) AS PATIENTS FROM BUH_HOL.INBOUND.PATIENT
UNION ALL
SELECT 'DEV',        COUNT(*)              FROM BUH_HOL.INBOUND.PATIENT_DEV;
-- Both show 100+ patients again.


-- ---- Step 5: Clean up ----
DROP TABLE BUH_HOL.INBOUND.PATIENT_DEV;


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
-- PART D: Semi-Structured & Unstructured Data
-- ============================================================

-- Healthcare generates massive amounts of JSON (FHIR APIs, device feeds,
-- lab result bundles) and free-text documents (clinical notes, discharge
-- summaries, radiology reports). Snowflake handles both natively — no
-- ETL to flatten JSON, no external NLP services to parse documents.

-- ---- Semi-structured: FHIR-style JSON in a VARIANT column ----

-- VARIANT columns store JSON, Avro, Parquet, or XML natively.
-- You query them with dot notation — no schema definition needed.

CREATE OR REPLACE TABLE BUH_HOL.INBOUND.CLINICAL_DOCUMENTS (
    PAT_ID         VARCHAR(20),
    DOC_DATE       DATE,
    CLINICAL_DATA  VARIANT,
    CLINICAL_NOTE  VARCHAR(2000)
);

INSERT INTO BUH_HOL.INBOUND.CLINICAL_DOCUMENTS
SELECT 'P100001', '2024-11-15', PARSE_JSON('{
  "vitals": {"heart_rate": 88, "bp_systolic": 142, "bp_diastolic": 90, "temp_f": 98.6, "o2_sat": 96},
  "allergies": ["Penicillin", "Sulfa drugs"],
  "medications": [
    {"name": "Lisinopril", "dose": "10mg", "frequency": "daily"},
    {"name": "Metformin", "dose": "500mg", "frequency": "twice daily"}
  ]
}'), 'Patient presents with elevated blood pressure. History of hypertension and type 2 diabetes. Currently managed with Lisinopril and Metformin. Plan: increase Lisinopril to 20mg, recheck in 2 weeks.'
UNION ALL
SELECT 'P100002', '2024-11-20', PARSE_JSON('{
  "vitals": {"heart_rate": 72, "bp_systolic": 118, "bp_diastolic": 76, "temp_f": 101.2, "o2_sat": 94},
  "allergies": [],
  "medications": [
    {"name": "Amoxicillin", "dose": "875mg", "frequency": "twice daily"}
  ]
}'), 'Patient presents with fever, productive cough for 3 days. Chest X-ray shows right lower lobe infiltrate consistent with community-acquired pneumonia. Started on Amoxicillin. Follow up in 48 hours if no improvement.'
UNION ALL
SELECT 'P100003', '2024-11-22', PARSE_JSON('{
  "vitals": {"heart_rate": 110, "bp_systolic": 95, "bp_diastolic": 60, "temp_f": 99.1, "o2_sat": 92},
  "allergies": ["Aspirin", "Iodine contrast"],
  "medications": [
    {"name": "Heparin", "dose": "5000 units", "frequency": "every 8 hours"},
    {"name": "Ondansetron", "dose": "4mg", "frequency": "as needed"}
  ]
}'), 'ED presentation with tachycardia and hypotension. CT angiogram confirms bilateral pulmonary embolism. Started on heparin drip. Admitting to ICU. Allergy to iodine contrast noted — premedicated with steroids.';

-- Query 1: Dot notation — access nested JSON like regular columns
SELECT
    PAT_ID,
    CLINICAL_DATA:vitals.heart_rate::INT       AS HEART_RATE,
    CLINICAL_DATA:vitals.bp_systolic::INT      AS BP_SYSTOLIC,
    CLINICAL_DATA:vitals.o2_sat::INT           AS O2_SAT,
    CLINICAL_DATA:allergies                    AS ALLERGIES,
    CLINICAL_DATA:medications                  AS MEDICATIONS
FROM BUH_HOL.INBOUND.CLINICAL_DOCUMENTS;

-- Query 2: LATERAL FLATTEN — explode medication arrays into rows
SELECT
    d.PAT_ID,
    m.value:name::VARCHAR      AS MEDICATION,
    m.value:dose::VARCHAR      AS DOSE,
    m.value:frequency::VARCHAR AS FREQUENCY
FROM BUH_HOL.INBOUND.CLINICAL_DOCUMENTS d,
    LATERAL FLATTEN(INPUT => d.CLINICAL_DATA:medications) m;

-- ---- Unstructured: read a PDF from the Git workspace ----

-- The Git repo contains a sample discharge summary PDF.
-- PARSE_DOCUMENT requires a regular stage (not a Git repo stage),
-- so we copy the file first, then extract text from it.

CREATE OR REPLACE STAGE BUH_HOL.INBOUND.DOC_STAGE;
COPY FILES
  INTO @BUH_HOL.INBOUND.DOC_STAGE
  FROM @BUH_HOL.INBOUND.LAB_REPO/branches/main/docs/discharge_summary_sample.pdf;

-- Extract the full text from the discharge summary
SELECT SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
    '@BUH_HOL.INBOUND.DOC_STAGE',
    'discharge_summary_sample.pdf',
    {'mode': 'LAYOUT'}
):content::VARCHAR AS EXTRACTED_TEXT;

-- Ask questions against the extracted document
SELECT SNOWFLAKE.CORTEX.EXTRACT_ANSWER(
    (SELECT SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
        '@BUH_HOL.INBOUND.DOC_STAGE',
        'discharge_summary_sample.pdf',
        {'mode': 'LAYOUT'}
    ):content::VARCHAR),
    'What medications was the patient discharged on?'
)[0]:answer::VARCHAR AS DISCHARGE_MEDICATIONS;

SELECT SNOWFLAKE.CORTEX.EXTRACT_ANSWER(
    (SELECT SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
        '@BUH_HOL.INBOUND.DOC_STAGE',
        'discharge_summary_sample.pdf',
        {'mode': 'LAYOUT'}
    ):content::VARCHAR),
    'What is the follow-up plan?'
)[0]:answer::VARCHAR AS FOLLOW_UP_PLAN;


-- ============================================================
-- PART E: Custom Python UDFs
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
-- PART F: Cortex AI Functions
-- ============================================================

-- Snowflake Cortex runs LLM-powered functions directly in SQL.
-- No API keys, no endpoints, no Python — just SQL.
--
-- In production, Snowflake also offers SNOWFLAKE.ML functions
-- (FORECAST, ANOMALY_DETECTION, CLASSIFICATION, REGRESSION) that
-- train and serve models entirely in-platform. Those require
-- Enterprise Edition and are not available in trial accounts.

-- ---- Classify diagnoses by clinical urgency ----

-- CLASSIFY_TEXT uses an LLM to categorize free-text into labels you define.
-- No training step needed — just pass the text and the categories.
SELECT
    e.ENCOUNTER_ID,
    e.PATIENT_NAME,
    e.PRIMARY_DIAGNOSIS,
    e.ED_HOURS,
    e.TOTAL_CHARGES,
    SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
        e.PRIMARY_DIAGNOSIS,
        ['Life-threatening', 'Urgent', 'Non-urgent']
    ):label::VARCHAR AS URGENCY_LEVEL
FROM BUH_HOL.DATAMARTS.ED_THROUGHPUT e
WHERE e.PRIMARY_DIAGNOSIS IS NOT NULL
LIMIT 10;

-- ---- Generate visit summaries using CORTEX.COMPLETE ----

-- COMPLETE calls a hosted LLM to generate free-text output.
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

-- Other Cortex AI functions available in SQL:
--   SNOWFLAKE.CORTEX.SENTIMENT()       — positive/negative/neutral
--   SNOWFLAKE.CORTEX.SUMMARIZE()       — condense long text
--   SNOWFLAKE.CORTEX.EXTRACT_ANSWER()  — Q&A over text
--   SNOWFLAKE.CORTEX.TRANSLATE()       — language translation

-- ============================================================
-- Beyond Cortex AI: Snowflake ML Functions
-- ============================================================
--
-- Snowflake also provides ML functions that train, deploy, and serve
-- models entirely inside Snowflake — no Python notebooks or external
-- infrastructure required. These require Enterprise Edition or higher.
--
--   SNOWFLAKE.ML.FORECAST()           — time series forecasting
--     Example: predict next month's ED visit volume by department
--
--   SNOWFLAKE.ML.ANOMALY_DETECTION()  — detect outliers in time series
--     Example: flag unusual spikes in lab order volumes or charges
--
--   SNOWFLAKE.ML.CLASSIFICATION()     — train/predict classifiers
--     Example: predict encounter type or readmission risk from patient data
--
--   SNOWFLAKE.ML.REGRESSION()         — train/predict continuous values
--     Example: estimate expected length of stay from diagnosis and acuity
--
-- Usage pattern (same for all):
--   1. CREATE SNOWFLAKE.ML.<TYPE> model_name(INPUT_DATA => ..., TARGET_COLNAME => ...)
--   2. SELECT model_name!PREDICT(INPUT_DATA => OBJECT_CONSTRUCT(*)) FROM ...
--
-- The model trains on step 1 and is immediately available for predictions
-- in step 2. No deployment pipeline, no model registry, no serving layer.
