/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 04: Tags, Sensitivity Labels & Governance

  GOAL: Create tags, apply them to Clarity source columns, set up
        tag-based masking and row access policies, test across roles.

  TIME: ~20 minutes
  PREREQUISITE: Run 01_setup.sql and 02_dynamic_tables.sql first
  EDITION: Enterprise Edition or higher (required for tags,
           masking policies, and row access policies)
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
--
-- Taggable objects include: warehouses, databases, schemas, tables,
-- views, columns, users, roles, stages, masking policies, and more.
-- Tags CANNOT be applied to individual rows.
-- Full list: https://docs.snowflake.com/en/sql-reference/sql/alter-tag

-- ============================================================
-- PART B: Create and apply tags
-- ============================================================

USE SCHEMA BUH_HOL.GOVERNANCE;

-- NOTE: CREATE OR REPLACE TAG drops all existing assignments of this tag.
-- In production, use CREATE TAG IF NOT EXISTS or ALTER TAG to avoid data loss.
CREATE OR REPLACE TAG PII_TYPE
  ALLOWED_VALUES = ('SSN', 'NAME', 'EMAIL', 'PHONE', 'ADDRESS', 'DOB', 'MRN')
  COMMENT = 'Type of personally identifiable information in a column.';

CREATE OR REPLACE TAG SENSITIVITY
  ALLOWED_VALUES = ('PUBLIC', 'INTERNAL', 'CONFIDENTIAL', 'RESTRICTED')
  COMMENT = 'Data sensitivity classification level.';

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
-- For real-time results, use named parameters:
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
--   REF_ENTITY_NAME  => 'BUH_HOL.INBOUND.PATIENT',
--   REF_ENTITY_DOMAIN => 'TABLE'));

-- ============================================================
-- PART D: Tag-based masking (column-level security)
-- ============================================================

-- The key pattern: attach a masking policy to a TAG, not to
-- individual columns. Every column with that tag is protected.
--
-- WHY IS_ROLE_IN_SESSION() instead of CURRENT_ROLE()?
-- IS_ROLE_IN_SESSION checks the full role hierarchy, including inherited
-- roles. CURRENT_ROLE() only returns the primary role, which can cause
-- unexpected masking behavior when users have complex role trees.

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

-- BIRTH_DATE is a DATE column, but MASK_PII_STRING expects VARCHAR.
-- Snowflake skips tag-based policies when the data type doesn't match,
-- so without MASK_DOB this column would be UNMASKED for all roles.
-- The column-level policy also takes precedence per the rule below.
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

-- POLICY PRECEDENCE:
-- When a column has BOTH a tag-based policy AND a direct column-level policy,
-- the column-level policy WINS. This lets us apply a general-purpose mask
-- (MASK_PII_STRING) via the PII_TYPE tag for most columns, then override
-- specific columns like SSN and BIRTH_DATE with specialized policies.
--
-- Precedence order (highest to lowest):
--   1. Column-level masking policy (set directly on the column)
--   2. Tag-based masking policy on the column's tag
--   3. Tag-based masking policy on the table's tag
ALTER TABLE BUH_HOL.INBOUND.PATIENT MODIFY COLUMN SSN
  SET MASKING POLICY BUH_HOL.GOVERNANCE.MASK_SSN;
ALTER TABLE BUH_HOL.INBOUND.PATIENT MODIFY COLUMN BIRTH_DATE
  SET MASKING POLICY BUH_HOL.GOVERNANCE.MASK_DOB;

-- ============================================================
-- PART E: Test masking across roles
-- ============================================================

-- Grant SELECT so each role can query the PATIENT table directly
-- (USAGE on database, schemas, and warehouse was granted in 01_setup.sql)
GRANT SELECT ON TABLE BUH_HOL.INBOUND.PATIENT TO ROLE BUH_LAB_ADMIN;
GRANT SELECT ON TABLE BUH_HOL.INBOUND.PATIENT TO ROLE BUH_LAB_CLINICIAN;
GRANT SELECT ON TABLE BUH_HOL.INBOUND.PATIENT TO ROLE BUH_LAB_ANALYST;

-- Disable secondary roles so the masking policies see ONLY the active role.
-- Without this, ACCOUNTADMIN's inherited roles make IS_ROLE_IN_SESSION()
-- return TRUE for every role, bypassing all masking.
USE SECONDARY ROLES NONE;

-- ADMIN sees everything
USE ROLE BUH_LAB_ADMIN;
USE WAREHOUSE BUH_ANALYTICS_WH;
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, EMAIL_ADDRESS, BIRTH_DATE
FROM BUH_HOL.INBOUND.PATIENT LIMIT 3;

-- CLINICIAN sees names/email, SSN last-4, DOB visible
USE ROLE BUH_LAB_CLINICIAN;
USE WAREHOUSE BUH_ANALYTICS_WH;
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, EMAIL_ADDRESS, BIRTH_DATE
FROM BUH_HOL.INBOUND.PATIENT LIMIT 3;

-- ANALYST sees ***MASKED*** names/email, ***-**-**** SSN, NULL DOB
USE ROLE BUH_LAB_ANALYST;
USE WAREHOUSE BUH_ANALYTICS_WH;
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
--
-- Row access policies are supported on dynamic tables, standard tables, and views.

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

-- Grant SELECT on FACT_ENCOUNTER to all lab roles
GRANT SELECT ON TABLE BUH_HOL.CORE_DATA.FACT_ENCOUNTER TO ROLE BUH_LAB_ADMIN;
GRANT SELECT ON TABLE BUH_HOL.CORE_DATA.FACT_ENCOUNTER TO ROLE BUH_LAB_CLINICIAN;
GRANT SELECT ON TABLE BUH_HOL.CORE_DATA.FACT_ENCOUNTER TO ROLE BUH_LAB_ANALYST;

USE SECONDARY ROLES NONE;

-- ADMIN sees all departments
USE ROLE BUH_LAB_ADMIN;
USE WAREHOUSE BUH_ANALYTICS_WH;
SELECT DEPARTMENT_NAME, COUNT(*) AS ENCOUNTER_COUNT
FROM BUH_HOL.CORE_DATA.FACT_ENCOUNTER GROUP BY DEPARTMENT_NAME ORDER BY ENCOUNTER_COUNT DESC;

-- CLINICIAN sees only Emergency Department rows
USE ROLE BUH_LAB_CLINICIAN;
USE WAREHOUSE BUH_ANALYTICS_WH;
SELECT DEPARTMENT_NAME, COUNT(*) AS ENCOUNTER_COUNT
FROM BUH_HOL.CORE_DATA.FACT_ENCOUNTER GROUP BY DEPARTMENT_NAME ORDER BY ENCOUNTER_COUNT DESC;

-- Restore
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;

-- ============================================================
-- CHECKPOINT — Expected results
-- ============================================================
--
--   ADMIN query:     Full SSN (e.g., 111-22-3333), real names, DOB dates
--   CLINICIAN query: SSN shows ***-**-3333, full names and email, DOB visible
--   ANALYST query:   SSN shows ***-**-****, names/email show ***MASKED***, DOB is NULL
--   Row access:      CLINICIAN sees ONLY 'Emergency Department', ADMIN/ANALYST see all depts

SHOW TAGS IN DATABASE BUH_HOL;
SHOW MASKING POLICIES IN DATABASE BUH_HOL;
