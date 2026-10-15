/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 07: Cleanup

  WARNING: This script permanently drops ALL lab objects.
  This action cannot be undone. Only run when you are finished with the lab.

  NOTE: In production, verify no active sessions are using these objects,
  confirm with stakeholders, and check Time Travel retention before dropping.
=============================================================================*/

USE ROLE ACCOUNTADMIN;

-- Remove tags applied to external objects (tag is defined inside BUH_HOL,
-- so we must unset before dropping the database that contains the tag)
ALTER WAREHOUSE BUH_ANALYTICS_WH UNSET TAG BUH_HOL.GOVERNANCE.COST_CENTER;
ALTER WAREHOUSE BUH_PIPELINE_WH UNSET TAG BUH_HOL.GOVERNANCE.COST_CENTER;
ALTER DATABASE BUH_HOL UNSET TAG BUH_HOL.GOVERNANCE.SENSITIVITY;

-- Unset resource monitor (only assigned to BUH_ANALYTICS_WH in this lab)
ALTER WAREHOUSE BUH_ANALYTICS_WH SET RESOURCE_MONITOR = NULL;

-- Suspend the audit task before dropping the database (best practice:
-- ensures no in-flight execution conflicts with the cascade drop)
ALTER TASK IF EXISTS BUH_HOL.INBOUND.LOG_PATIENT_CHANGES SUSPEND;

-- Drop the lab database (cascades: all schemas, tables, dynamic tables,
-- tags, policies, streams, tasks, stages, Git repo objects inside it)
DROP DATABASE IF EXISTS BUH_HOL;

-- Drop resource monitor (account-level object, not inside the database)
DROP RESOURCE MONITOR IF EXISTS BUH_LAB_MONITOR;

-- Drop lab warehouses
DROP WAREHOUSE IF EXISTS BUH_PIPELINE_WH;
DROP WAREHOUSE IF EXISTS BUH_ANALYTICS_WH;

-- Drop lab roles
DROP ROLE IF EXISTS BUH_LAB_ADMIN;
DROP ROLE IF EXISTS BUH_LAB_ANALYST;
DROP ROLE IF EXISTS BUH_LAB_CLINICIAN;

-- Drop the Git API integration (account-level object)
DROP API INTEGRATION IF EXISTS github_buh_lab;

-- ============================================================
-- Verify cleanup
-- ============================================================
SHOW DATABASES LIKE 'BUH_HOL';
SHOW WAREHOUSES LIKE 'BUH_%';
SHOW ROLES LIKE 'BUH_LAB_%';
SHOW RESOURCE MONITORS LIKE 'BUH_LAB_%';
SHOW INTEGRATIONS LIKE 'github_buh_lab';
-- All queries above should return 0 rows.
