/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 01: Shared Workspaces & Git Integration (Hands-On)

  GOAL: Connect a Git repo as a Snowflake workspace, browse files,
        and run the setup script directly from the repository.

  TIME: ~15 minutes
  PREREQUISITE: Snowflake account with ACCOUNTADMIN

  NOTE: The instructor will walk through the API integration setup.
        Attendees will browse and run files from the connected repo.
=============================================================================*/

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================
-- PART A: What are workspaces?
-- ============================================================

-- Workspaces connect a Git repo (GitHub, GitLab, Azure DevOps)
-- directly to your Snowflake account. You can:
--   1. Browse repo files in Snowsight like a file system
--   2. Run .sql files without downloading or copy-pasting
--   3. Fetch the latest changes from Git at any time
--   4. Share versioned code across your entire team
--
-- This lab itself is delivered via a Git workspace.
-- You are about to connect the lab repo and run scripts from it.

-- ============================================================
-- PART B: Create the Git integration (instructor-led)
-- ============================================================

-- Step 1: API integration - connects Snowflake to GitHub
CREATE OR REPLACE API INTEGRATION github_buh_lab
  API_PROVIDER = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/daltonryan6/')
  ENABLED = TRUE;

-- Step 2: Create a database for our lab (needed before creating the repo object)
CREATE OR REPLACE DATABASE BUH_HOL;
CREATE SCHEMA IF NOT EXISTS BUH_HOL.INBOUND;

-- Step 3: Git repository object - points to the lab repo
CREATE OR REPLACE GIT REPOSITORY BUH_HOL.INBOUND.LAB_REPO
  API_INTEGRATION = github_buh_lab
  ORIGIN = 'https://github.com/daltonryan6/buh-hol.git';

-- ============================================================
-- PART C: Explore the repo (everyone does this)
-- ============================================================

-- Fetch latest from remote
ALTER GIT REPOSITORY BUH_HOL.INBOUND.LAB_REPO FETCH;

-- List branches
SHOW GIT BRANCHES IN BUH_HOL.INBOUND.LAB_REPO;

-- Browse the repo root
LS @BUH_HOL.INBOUND.LAB_REPO/branches/main/;

-- Browse the scripts folder - these are the files we will run today
LS @BUH_HOL.INBOUND.LAB_REPO/branches/main/scripts/;

-- ============================================================
-- PART D: Run the setup script FROM the repo
-- ============================================================

-- This is the key moment: instead of copy-pasting SQL,
-- you execute it directly from the versioned repository.
-- Everyone on the team runs the same code, every time.

-- Drop the database we just created (the setup script recreates it)
DROP DATABASE IF EXISTS BUH_HOL;

-- Run the full setup from the repo
EXECUTE IMMEDIATE FROM @BUH_HOL.INBOUND.LAB_REPO/branches/main/scripts/00_setup.sql;

-- NOTE: If the EXECUTE IMMEDIATE fails because BUH_HOL was just dropped,
-- run 00_setup.sql manually from the worksheet instead. The Git integration
-- and repo object will be recreated after setup completes.

-- ============================================================
-- PART E: Verify setup worked
-- ============================================================

SELECT 'PATIENT' AS TBL, COUNT(*) AS ROWS FROM BUH_HOL.INBOUND.PATIENT
UNION ALL SELECT 'PAT_ENC', COUNT(*) FROM BUH_HOL.INBOUND.PAT_ENC
UNION ALL SELECT 'CLARITY_SER', COUNT(*) FROM BUH_HOL.INBOUND.CLARITY_SER
UNION ALL SELECT 'ORDER_PROC', COUNT(*) FROM BUH_HOL.INBOUND.ORDER_PROC
UNION ALL SELECT 'HSP_ACCT_DX_LIST', COUNT(*) FROM BUH_HOL.INBOUND.HSP_ACCT_DX_LIST
ORDER BY TBL;

-- ============================================================
-- PART F: Why this matters for your team
-- ============================================================

-- Without Git workspaces:
--   - SQL lives in local files, Slack, shared drives
--   - No version history, no code review, no rollback
--   - "Which version is in prod?" is unanswerable
--   - Onboarding means copying files around
--
-- With Git workspaces:
--   - SQL is versioned in Git alongside everything else
--   - Changes go through pull requests and review
--   - Any team member can clone and run the latest code
--   - Deployments are traceable: commit abc123 is in prod
--
-- For your Snowforge workflow: Git workspaces give you the
-- version control layer. Combined with dynamic tables (next step),
-- you can replace scheduled transformation scripts with
-- declarative SQL that auto-refreshes.

-- ============================================================
-- CHECKPOINT
-- ============================================================

-- You should be able to:
--   1. See the Git repo object in Snowsight (Data > BUH_HOL > Stages)
--   2. Browse the scripts/ folder
--   3. Have all 5 INBOUND tables populated with Clarity data
--   4. Understand how Git workspaces replace file-share chaos
