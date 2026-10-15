/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 05: Power BI, Iceberg Tables & Microsoft Fabric

  GOAL: Understand the three Power BI connection options, create an
        Iceberg table, and discuss Fabric CU cost management.

  TIME: ~15 minutes (one hands-on Iceberg CTAS + guided discussion)
  PREREQUISITE: Run 01_setup.sql and 02_dynamic_tables.sql first
                (DATAMARTS.DEPARTMENT_DASHBOARD must exist)
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
--   PBI reads Parquet files via Direct Lake — no SF warehouse for BI reads.
--   Snowflake still uses a warehouse to WRITE/REFRESH the Iceberg table,
--   but that's a scheduled pipeline cost, not per-dashboard-interaction.
--   Pro: No SF compute for BI reads, open format
--   Con: Requires Fabric capacity, setup complexity
--   Best for: Minimizing Snowflake compute for BI workloads

-- ============================================================
-- PART B: Fabric CU overconsumption - what to watch for
-- ============================================================

-- All Fabric workloads share one Capacity Unit (CU) pool.
-- Direct Lake reads, Dataflows, Spark, SQL endpoints — all pull
-- from the same pool. If the pool is exhausted:
--   - Interactive queries slow down or queue
--   - Background refreshes get delayed
--   - In extreme cases, operations can be rejected entirely
--
-- CHEAPEST PATH for BUH:
--   1. Keep pipeline (INBOUND -> CORE_DATA -> DATAMARTS) in Snowflake
--      using dynamic tables (you just built this!)
--   2. Write only the DATAMARTS layer out as Iceberg to OneLake
--   3. Power BI reads from Direct Lake — no Snowflake queries
--   4. Size Fabric capacity for BI read load only

-- ============================================================
-- PART C: Iceberg table - hands-on
-- ============================================================

-- Snowflake-managed Iceberg: Snowflake manages the catalog and storage.
-- Other Iceberg setups can use your cloud storage and/or an external catalog.
-- Both use the Iceberg format; the difference is who manages the storage/catalog.
-- Supported external engines can also access Snowflake-managed tables via Horizon Catalog.

CREATE OR REPLACE ICEBERG TABLE BUH_HOL.DATAMARTS.DEPT_DASHBOARD_ICEBERG
  CATALOG = 'SNOWFLAKE'
AS
SELECT * FROM BUH_HOL.DATAMARTS.DEPARTMENT_DASHBOARD;

-- Query it just like a regular table
SELECT * FROM BUH_HOL.DATAMARTS.DEPT_DASHBOARD_ICEBERG ORDER BY TOTAL_CHARGES DESC;

-- Column metadata (same as any table)
DESCRIBE TABLE BUH_HOL.DATAMARTS.DEPT_DASHBOARD_ICEBERG;

-- Iceberg-specific properties (catalog, storage, format version)
SHOW ICEBERG TABLES LIKE 'DEPT_DASHBOARD_ICEBERG' IN SCHEMA BUH_HOL.DATAMARTS;

-- ============================================================
-- PART D: OneLake integration (reference only)
-- ============================================================

-- This pattern uses Snowflake as the Iceberg catalog and stores the
-- table files in OneLake through an external volume.
-- OneLake can expose Iceberg tables as Delta-compatible tables for
-- Fabric workloads, including supported Direct Lake scenarios.
-- The example below is illustrative; follow the current setup guide
-- for the OneLake URL, permissions, and authentication.
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

-- RAW/INBOUND -> Snowflake native
--                 Simple Snowflake-first ingestion and broad native features.
--
-- CORE_DATA   -> Snowflake native when native Dynamic Tables or broader
--                 Snowflake feature support is the priority.
--                 Dynamic Iceberg Tables are also available; evaluate their
--                 additional requirements and limitations.
--
-- DATAMARTS   -> Iceberg in OneLake when Fabric interoperability is a goal.
--                 Fabric can use OneLake's Iceberg-to-Delta compatibility.
--                 Power BI reads OneLake directly; Snowflake compute is still
--                 used for Snowflake-side writes and transformations.

-- ============================================================
-- CHECKPOINT
-- ============================================================

-- Verify the Iceberg table exists and has data:
SELECT COUNT(*) AS ROW_COUNT FROM BUH_HOL.DATAMARTS.DEPT_DASHBOARD_ICEBERG;
SHOW ICEBERG TABLES LIKE 'DEPT_DASHBOARD_ICEBERG' IN SCHEMA BUH_HOL.DATAMARTS;

-- You should understand:
--   1. Three PBI options and when to use each
--   2. Why Fabric CU overconsumption happens
--   3. Snowflake-managed Iceberg vs external-volume Iceberg
--   4. The recommended hybrid pattern: SF pipeline + Iceberg datamarts + Fabric BI
