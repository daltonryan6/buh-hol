/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 04: Tags, Sensitivity Labels & Governance

  GOAL: Create tags, apply them to Clarity source columns, set up
        tag-based masking, and test masking across roles.

  TIME: ~20 minutes
  PREREQUISITE: Run 00_setup.sql and 02_dynamic_tables.sql first
=============================================================================*/

USE DATABASE BUH_HOL;
USE WAREHOUSE COMPUTE_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- PART A: Where can tags be applied?
-- ============================================================

-- Tags are key-value metadata on Snowflake objects:
--   Warehouses  -> cost_center = 'Research'
--   Databases   -> data_domain = 'Clinical'
--   Schemas     -> data_layer  = 'INBOUND'
--   Tables      -> contains_phi = 'Yes'
--   Columns     -> pii_type    = 'SSN'
--
-- Tags CANNOT be applied to rows, stages, users, or roles.

-- ============================================================
-- PART B: Create and apply tags
-- ============================================================

USE SCHEMA BUH_HOL.GOVERNANCE;

CREATE OR REPLACE TAG PII_TYPE
  ALLOWED_VALUES = 'SSN', 'NAME', 'EMAIL', 'PHONE', 'ADDRESS', 'DOB', 'MRN'
  COMMENT = 'Type of personally identifiable information in a column.';

CREATE OR REPLACE TAG SENSITIVITY
  ALLOWED_VALUES = 'PUBLIC', 'INTERNAL', 'CONFIDENTIAL', 'RESTRICTED'
  COMMENT = 'Data sensitivity classification level.';

CREATE OR REPLACE TAG COST_CENTER
  COMMENT = 'Department or team responsible for warehouse costs.';

-- Apply to objects
ALTER DATABASE BUH_HOL SET TAG BUH_HOL.GOVERNANCE.SENSITIVITY = 'CONFIDENTIAL';
ALTER WAREHOUSE COMPUTE_WH SET TAG BUH_HOL.GOVERNANCE.COST_CENTER = 'Analytics';

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

-- ADMIN sees everything
EXECUTE USING POLICY_CONTEXT(CURRENT_ROLE => 'BUH_LAB_ADMIN')
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, EMAIL_ADDRESS, BIRTH_DATE
FROM BUH_HOL.INBOUND.PATIENT LIMIT 3;

-- CLINICIAN sees names/email, SSN last-4, DOB visible
EXECUTE USING POLICY_CONTEXT(CURRENT_ROLE => 'BUH_LAB_CLINICIAN')
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, EMAIL_ADDRESS, BIRTH_DATE
FROM BUH_HOL.INBOUND.PATIENT LIMIT 3;

-- ANALYST sees ***MASKED*** names/email, ***-**-**** SSN, NULL DOB
EXECUTE USING POLICY_CONTEXT(CURRENT_ROLE => 'BUH_LAB_ANALYST')
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, EMAIL_ADDRESS, BIRTH_DATE
FROM BUH_HOL.INBOUND.PATIENT LIMIT 3;

-- ============================================================
-- PART F: Tags vs Purview labels (quick reference)
-- ============================================================

-- Snowflake Tags:     Applied in Snowflake. Drive masking & access.
-- Purview Labels:     Applied in Microsoft. Drive DLP & encryption.
-- Auto-sync?          NO. Separate systems. Align manually.
-- Purview scans SF?   YES. Tables, views, lineage all discoverable.

-- ============================================================
-- CHECKPOINT
-- ============================================================

-- You should see:
--   - Tags applied to INBOUND.PATIENT columns
--   - Tag-based masking protecting all PII columns at once
--   - ADMIN sees full data, CLINICIAN sees partial, ANALYST sees masked
--   - Understand that Snowflake tags and Purview labels are separate

SHOW TAGS IN DATABASE BUH_HOL;
SHOW MASKING POLICIES IN DATABASE BUH_HOL;
