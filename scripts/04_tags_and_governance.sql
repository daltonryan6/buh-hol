/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 04: Tags, Sensitivity Labels & Governance

  GOAL: Create tags, apply them to Clarity source columns, set up
        tag-based masking, and test masking across roles.

  TIME: ~20 minutes
  PREREQUISITE: Run 01_setup.sql and 02_dynamic_tables.sql first
=============================================================================*/

USE DATABASE BUH_HOL;
USE WAREHOUSE BUH_ANALYTICS_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- PART A: What are tags?
-- ============================================================

-- Tags are key-value labels you attach to Snowflake objects —
-- databases, schemas, tables, columns, warehouses, even roles.
-- They serve two purposes:
--
--   1. CLASSIFICATION: Label what data is (PII, PHI, sensitivity level)
--      so you can discover and audit sensitive data across your account.
--
--   2. POLICY ENFORCEMENT: Attach masking policies or row access policies
--      to a tag instead of individual columns/tables. Every object with
--      that tag is automatically protected — add a tag, get protection.
--
-- Tags are defined with optional ALLOWED_VALUES to enforce consistency.
-- Example: PII_TYPE can only be 'SSN', 'NAME', 'EMAIL', etc.

-- Where can tags be applied?
--   Warehouses  -> cost_center = 'Research'
--   Databases   -> data_domain = 'Clinical'
--   Schemas     -> data_layer  = 'INBOUND'
--   Tables      -> contains_phi = 'Yes'
--   Columns     -> pii_type    = 'SSN'
--
-- Tags CANNOT be applied to individual rows.
-- Tags CAN be applied to users, roles, stages, warehouses, and many other objects.

-- ============================================================
-- PART B: Create and apply tags
-- ============================================================

USE SCHEMA BUH_HOL.GOVERNANCE;

CREATE OR REPLACE TAG PII_TYPE
  COMMENT = 'Type of personally identifiable information in a column.';
ALTER TAG PII_TYPE SET ALLOWED_VALUES 'SSN', 'NAME', 'EMAIL', 'PHONE', 'ADDRESS', 'DOB', 'MRN';

CREATE OR REPLACE TAG SENSITIVITY
  COMMENT = 'Data sensitivity classification level.';
ALTER TAG SENSITIVITY SET ALLOWED_VALUES 'PUBLIC', 'INTERNAL', 'CONFIDENTIAL', 'RESTRICTED';

CREATE OR REPLACE TAG COST_CENTER
  COMMENT = 'Department or team responsible for warehouse costs.';

-- Apply to objects
ALTER DATABASE BUH_HOL SET TAG BUH_HOL.GOVERNANCE.SENSITIVITY = 'CONFIDENTIAL';
ALTER WAREHOUSE BUH_PIPELINE_WH SET TAG BUH_HOL.GOVERNANCE.COST_CENTER = 'Pipeline';
ALTER WAREHOUSE BUH_ANALYTICS_WH SET TAG BUH_HOL.GOVERNANCE.COST_CENTER = 'Analytics';

-- Tag sensitive columns in the Clarity PATIENT table
ALTER TABLE BUH_HOL.INBOUND.PATIENT MODIFY COLUMN SSN
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'SSN';
ALTER TABLE BUH_HOL.INBOUND.PATIENT MODIFY COLUMN SSN
  SET TAG BUH_HOL.GOVERNANCE.SENSITIVITY = 'RESTRICTED';
ALTER TABLE BUH_HOL.INBOUND.PATIENT MODIFY COLUMN PAT_FIRST_NAME
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'NAME';
ALTER TABLE BUH_HOL.INBOUND.PATIENT MODIFY COLUMN PAT_LAST_NAME
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'NAME';
ALTER TABLE BUH_HOL.INBOUND.PATIENT MODIFY COLUMN EMAIL_ADDRESS
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'EMAIL';
ALTER TABLE BUH_HOL.INBOUND.PATIENT MODIFY COLUMN HOME_PHONE
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'PHONE';
ALTER TABLE BUH_HOL.INBOUND.PATIENT MODIFY COLUMN ADD_LINE_1
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'ADDRESS';
ALTER TABLE BUH_HOL.INBOUND.PATIENT MODIFY COLUMN BIRTH_DATE
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'DOB';
ALTER TABLE BUH_HOL.INBOUND.PATIENT MODIFY COLUMN PAT_MRN_ID
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'MRN';

-- ============================================================
-- PART C: Find all PII columns
-- ============================================================

SELECT
    OBJECT_NAME AS TABLE_NAME, COLUMN_NAME, TAG_VALUE AS PII_TYPE
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE TAG_NAME = 'PII_TYPE' AND DOMAIN = 'COLUMN'
  AND OBJECT_DATABASE = 'BUH_HOL'
ORDER BY TABLE_NAME, COLUMN_NAME;

-- NOTE: ACCOUNT_USAGE views can have up to 2-hour latency.
-- For real-time results, use:
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
--   'BUH_HOL.INBOUND.PATIENT', 'TABLE'));

-- ============================================================
-- PART D: Tag-based masking
-- ============================================================

-- The key pattern: attach a masking policy to a TAG, not to
-- individual columns. Every column with that tag is protected.

CREATE OR REPLACE MASKING POLICY BUH_HOL.GOVERNANCE.MASK_PII_STRING
  AS (val VARCHAR) RETURNS VARCHAR ->
  CASE
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_CLINICIAN') THEN val
    ELSE '***MASKED***'
  END;

CREATE OR REPLACE MASKING POLICY BUH_HOL.GOVERNANCE.MASK_SSN
  AS (val VARCHAR) RETURNS VARCHAR ->
  CASE
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_CLINICIAN') THEN '***-**-' || RIGHT(val, 4)
    ELSE '***-**-****'
  END;

CREATE OR REPLACE MASKING POLICY BUH_HOL.GOVERNANCE.MASK_DOB
  AS (val DATE) RETURNS DATE ->
  CASE
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_CLINICIAN') THEN val
    ELSE NULL
  END;

-- Attach the string mask to the PII_TYPE tag
ALTER TAG BUH_HOL.GOVERNANCE.PII_TYPE SET
  MASKING POLICY BUH_HOL.GOVERNANCE.MASK_PII_STRING;

-- SSN and DOB need direct policies (different masking behavior)
ALTER TABLE BUH_HOL.INBOUND.PATIENT MODIFY COLUMN SSN
  SET MASKING POLICY BUH_HOL.GOVERNANCE.MASK_SSN;
ALTER TABLE BUH_HOL.INBOUND.PATIENT MODIFY COLUMN BIRTH_DATE
  SET MASKING POLICY BUH_HOL.GOVERNANCE.MASK_DOB;

-- ============================================================
-- PART E: Test masking across roles
-- ============================================================

-- Grant SELECT so each role can query the PATIENT table directly
GRANT SELECT ON TABLE BUH_HOL.INBOUND.PATIENT TO ROLE BUH_LAB_ADMIN;
GRANT SELECT ON TABLE BUH_HOL.INBOUND.PATIENT TO ROLE BUH_LAB_CLINICIAN;
GRANT SELECT ON TABLE BUH_HOL.INBOUND.PATIENT TO ROLE BUH_LAB_ANALYST;

-- Disable secondary roles so the masking policies see ONLY the active role.
-- Without this, ACCOUNTADMIN's inherited roles make IS_ROLE_IN_SESSION()
-- return TRUE for every role, bypassing all masking.
USE SECONDARY ROLES NONE;

-- ADMIN sees everything
USE ROLE BUH_LAB_ADMIN;
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, EMAIL_ADDRESS, BIRTH_DATE
FROM BUH_HOL.INBOUND.PATIENT LIMIT 3;

-- CLINICIAN sees names/email, SSN last-4, DOB visible
USE ROLE BUH_LAB_CLINICIAN;
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, EMAIL_ADDRESS, BIRTH_DATE
FROM BUH_HOL.INBOUND.PATIENT LIMIT 3;

-- ANALYST sees ***MASKED*** names/email, ***-**-**** SSN, NULL DOB
USE ROLE BUH_LAB_ANALYST;
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, EMAIL_ADDRESS, BIRTH_DATE
FROM BUH_HOL.INBOUND.PATIENT LIMIT 3;

-- Restore full access for remaining lab steps
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;

-- ============================================================
-- PART F: Row Access Policies — row-level security
-- ============================================================

-- Column masking hides WHAT you see in a column.
-- Row access policies control WHICH ROWS you see at all.
--
-- Example: clinicians should only see encounters in their department,
-- analysts should see all departments for reporting.

CREATE OR REPLACE ROW ACCESS POLICY BUH_HOL.GOVERNANCE.DEPARTMENT_ACCESS
  AS (department_name VARCHAR) RETURNS BOOLEAN ->
  CASE
    -- Admins and analysts see all rows (analysts need full data for reporting)
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_ADMIN') THEN TRUE
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_ANALYST') THEN TRUE
    -- Clinicians only see Emergency Department rows (simulating department-level access)
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_CLINICIAN') THEN department_name = 'Emergency Department'
    ELSE FALSE
  END;

-- Apply to the FACT_ENCOUNTER dynamic table
ALTER TABLE BUH_HOL.CORE_DATA.FACT_ENCOUNTER
  ADD ROW ACCESS POLICY BUH_HOL.GOVERNANCE.DEPARTMENT_ACCESS
  ON (DEPARTMENT_NAME);

-- Test: grant SELECT on FACT_ENCOUNTER to all lab roles
GRANT SELECT ON TABLE BUH_HOL.CORE_DATA.FACT_ENCOUNTER TO ROLE BUH_LAB_ADMIN;
GRANT SELECT ON TABLE BUH_HOL.CORE_DATA.FACT_ENCOUNTER TO ROLE BUH_LAB_CLINICIAN;
GRANT SELECT ON TABLE BUH_HOL.CORE_DATA.FACT_ENCOUNTER TO ROLE BUH_LAB_ANALYST;

USE SECONDARY ROLES NONE;

-- ADMIN sees all departments
USE ROLE BUH_LAB_ADMIN;
SELECT DEPARTMENT_NAME, COUNT(*) AS ENCOUNTER_COUNT
FROM BUH_HOL.CORE_DATA.FACT_ENCOUNTER GROUP BY DEPARTMENT_NAME ORDER BY ENCOUNTER_COUNT DESC;

-- CLINICIAN sees only Emergency Department rows
USE ROLE BUH_LAB_CLINICIAN;
SELECT DEPARTMENT_NAME, COUNT(*) AS ENCOUNTER_COUNT
FROM BUH_HOL.CORE_DATA.FACT_ENCOUNTER GROUP BY DEPARTMENT_NAME ORDER BY ENCOUNTER_COUNT DESC;

-- Restore
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;

-- ============================================================
-- CHECKPOINT
-- ============================================================

-- You should see:
--   - Tags applied to INBOUND.PATIENT columns
--   - Column masking: ADMIN full, CLINICIAN partial SSN, ANALYST all masked
--   - Row access: CLINICIAN sees only ED rows, ADMIN/ANALYST see all

SHOW TAGS IN DATABASE BUH_HOL;
SHOW MASKING POLICIES IN DATABASE BUH_HOL;
