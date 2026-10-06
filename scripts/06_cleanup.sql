/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 06: Cleanup

  Removes all lab objects created during the session.
  Run this when you are finished with the lab.
=============================================================================*/

USE ROLE ACCOUNTADMIN;

-- Remove warehouse tag before dropping (avoids orphaned tag references)
ALTER WAREHOUSE COMPUTE_WH UNSET TAG BUH_HOL.GOVERNANCE.COST_CENTER;

-- Drop the lab database (drops all schemas, tables, dynamic tables, tags, policies)
DROP DATABASE IF EXISTS BUH_HOL;

-- Drop lab roles
DROP ROLE IF EXISTS BUH_LAB_ADMIN;
DROP ROLE IF EXISTS BUH_LAB_ANALYST;
DROP ROLE IF EXISTS BUH_LAB_CLINICIAN;

-- Drop the Git integration
DROP API INTEGRATION IF EXISTS github_buh_lab;

-- NOTE: COMPUTE_WH is NOT dropped - it is a shared resource.
-- If you created it just for this lab, uncomment:
-- DROP WAREHOUSE IF EXISTS COMPUTE_WH;
