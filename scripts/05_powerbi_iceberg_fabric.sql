/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 05: Power BI, Iceberg Tables & Microsoft Fabric

  GOAL: Understand the three Power BI connection options, create an
        Iceberg table, and discuss Fabric CU cost management.

  TIME: ~15 minutes (one hands-on Iceberg CTAS + guided discussion)
  PREREQUISITE: Run 01_setup.sql and 02_dynamic_tables.sql first
=============================================================================*/

USE DATABASE BUH_HOL;
USE WAREHOUSE BUH_ANALYTICS_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- PART A: Three ways to connect Power BI to Snowflake
-- ============================================================

-- OPTION 1: DirectQuery
--   PBI sends SQL to Snowflake at query time
--   Pro: Always fresh
--   Con: Warehouse runs during every dashboard interaction
--   Best for: Operational dashboards with moderate concurrency

-- OPTION 2: Import Mode
--   PBI extracts data into its in-memory engine on a schedule
--   Pro: Fast dashboards, warehouse only runs during refresh
--   Con: Data is stale between refreshes
--   Best for: Executive/strategic dashboards refreshed daily

-- OPTION 3: Snowflake + OneLake + Direct Lake (Fabric)
--   Snowflake writes Iceberg tables to Microsoft OneLake
--   PBI reads Parquet files via Direct Lake - no Snowflake warehouse
--   Pro: No SF compute for BI reads, open format
--   Con: Requires Fabric capacity, setup complexity
--   Best for: Minimizing Snowflake compute for BI workloads

-- ============================================================
-- PART B: Fabric CU overconsumption - what to watch for
-- ============================================================

-- All Fabric workloads share one Capacity Unit (CU) pool.
-- Direct Lake reads, Dataflows, Spark, SQL endpoints - all pull
-- from the same pool. If the pool is exhausted, workloads throttle.
--
-- CHEAPEST PATH for BUH:
--   1. Keep pipeline (INBOUND -> CORE_DATA -> DATAMARTS) in Snowflake
--      using dynamic tables (you just built this!)
--   2. Write only the DATAMARTS layer out as Iceberg to OneLake
--   3. Power BI reads from Direct Lake - no Snowflake queries
--   4. Size Fabric capacity for BI read load only

-- ============================================================
-- PART C: Iceberg table - hands-on
-- ============================================================

-- Iceberg tables use the same SQL as regular tables, but data is
-- stored in open Parquet format with Iceberg metadata. Any engine
-- that reads Iceberg (Fabric, Spark, Trino) can access it.

CREATE OR REPLACE ICEBERG TABLE BUH_HOL.DATAMARTS.DEPT_DASHBOARD_ICEBERG
  CATALOG = 'SNOWFLAKE'
AS
SELECT * FROM BUH_HOL.DATAMARTS.DEPARTMENT_DASHBOARD;

-- Query it just like a regular table
SELECT * FROM BUH_HOL.DATAMARTS.DEPT_DASHBOARD_ICEBERG ORDER BY TOTAL_CHARGES DESC;

-- See the Iceberg metadata
DESCRIBE TABLE BUH_HOL.DATAMARTS.DEPT_DASHBOARD_ICEBERG;

-- ============================================================
-- PART D: OneLake integration (reference - not hands-on)
-- ============================================================

-- To write Iceberg to OneLake for Direct Lake:
--
-- CREATE EXTERNAL VOLUME onelake_vol
-- STORAGE_LOCATIONS = (
--   (
--     NAME = 'fabric_onelake'
--     STORAGE_PROVIDER = 'AZURE'
--     STORAGE_BASE_URL = 'azure://onelake.dfs.fabric.microsoft.com/...'
--     AZURE_TENANT_ID = '<tenant-id>'
--   )
-- );
--
-- CREATE ICEBERG TABLE DATAMARTS.PATIENT_SUMMARY_ICEBERG
--   CATALOG = 'SNOWFLAKE'
--   EXTERNAL_VOLUME = 'onelake_vol'
--   BASE_LOCATION = 'patient_summary/'
-- AS SELECT * FROM DATAMARTS.DEPARTMENT_DASHBOARD;

-- ============================================================
-- PART E: When to use which table type
-- ============================================================

-- RAW/INBOUND  -> Snowflake default (fast ingest, time travel, streams)
-- CORE_DATA      -> Snowflake default (dynamic tables, joins, transforms)
-- DATAMARTS      -> Iceberg in OneLake (open format, Direct Lake, no SF compute)

-- ============================================================
-- CHECKPOINT
-- ============================================================

-- You should understand:
--   1. Three PBI options and when to use each
--   2. Why Fabric CU overconsumption happens
--   3. How Iceberg tables work (same SQL, open Parquet format)
--   4. The recommended hybrid pattern for BUH

SELECT * FROM BUH_HOL.DATAMARTS.DEPT_DASHBOARD_ICEBERG ORDER BY TOTAL_CHARGES DESC;
