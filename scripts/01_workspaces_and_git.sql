/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 01: Shared Workspaces & Git Integration
  
  GOAL: Understand how to use Snowflake Git-based workspaces to
        manage, version, and publish SQL code as a team.
  
  TIME: ~15 minutes
  PREREQUISITE: Run 00_setup.sql first
  
  NOTE: This module is primarily a walkthrough. The SQL below
        demonstrates the key concepts, but the real value is
        in the workflow you see in the Snowflake UI.
=============================================================================*/

USE DATABASE BUH_HOL;
USE WAREHOUSE COMPUTE_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- PART A: What are workspaces?
-- ============================================================

-- Workspaces are Snowflake's built-in way to connect a Git repo
-- to your Snowflake account. You can:
--   1. Clone a repo (GitHub, GitLab, Azure DevOps, Bitbucket)
--   2. Browse and run .sql files directly in Snowsight
--   3. Publish changes back to Git
--   4. Share versioned code across your team

-- This lab itself was delivered via a Git workspace.
-- The scripts you are running right now live in a Git repo.

-- ============================================================
-- PART B: Create a Git integration (instructor demo)
-- ============================================================

-- Step 1: Create an API integration for GitHub
-- (This is what connects Snowflake to your Git provider)

-- CREATE OR REPLACE API INTEGRATION github_integration
--   API_PROVIDER = GIT_HTTPS_API
--   API_ALLOWED_PREFIXES = ('https://github.com/daltonryan6/')
--   ENABLED = TRUE;

-- Step 2: Create a Git repository object
-- CREATE OR REPLACE GIT REPOSITORY BUH_HOL.RAW.LAB_REPO
--   API_INTEGRATION = github_integration
--   ORIGIN = 'https://github.com/daltonryan6/buh-hol.git';

-- Step 3: Fetch latest from remote
-- ALTER GIT REPOSITORY BUH_HOL.RAW.LAB_REPO FETCH;

-- Step 4: List branches and files
-- SHOW GIT BRANCHES IN BUH_HOL.RAW.LAB_REPO;
-- LS @BUH_HOL.RAW.LAB_REPO/branches/main/scripts/;

-- ============================================================
-- PART C: Key workspace concepts
-- ============================================================

-- 1. BROWSING FILES
-- In Snowsight, navigate to: Data > Databases > BUH_HOL > 
-- Stages > LAB_REPO. You can browse the repo like a file system.

-- 2. RUNNING SQL FROM A REPO
-- You can execute SQL files directly from the stage:
-- EXECUTE IMMEDIATE FROM @BUH_HOL.RAW.LAB_REPO/branches/main/scripts/00_setup.sql;

-- 3. WORKSPACES IN CORTEX CODE
-- Cortex Code connects to Git natively. You can:
--   - Open a workspace from a Git repo
--   - Edit files with AI assistance
--   - Commit and push changes
--   - Run SQL directly against Snowflake

-- ============================================================
-- PART D: Practical exercise - explore the repo
-- ============================================================

-- If a Git repository object has been configured, try these:

-- List what is in the repo
-- LS @BUH_HOL.RAW.LAB_REPO/branches/main/;

-- See the scripts
-- LS @BUH_HOL.RAW.LAB_REPO/branches/main/scripts/;

-- Read a file's contents
-- SELECT $1 FROM @BUH_HOL.RAW.LAB_REPO/branches/main/README.md
-- (FILE_FORMAT => (TYPE=CSV FIELD_DELIMITER=NONE RECORD_DELIMITER=NONE));

-- ============================================================
-- PART E: Why this matters for your team
-- ============================================================

-- Without Git workspaces:
--   - SQL lives in local files, Slack messages, or shared drives
--   - No version history, no code review, no rollback
--   - "Which version is in prod?" is unanswerable
--   - Onboarding a new analyst means copying files around

-- With Git workspaces:
--   - SQL is versioned in Git alongside everything else
--   - Changes go through pull requests and review
--   - Any team member can clone and run the latest code
--   - Deployments are traceable: "commit abc123 is in prod"

-- ============================================================
-- CHECKPOINT
-- ============================================================

-- You should understand:
--   1. What a Git integration and Git repository object are
--   2. How to browse and run SQL files from a repo in Snowsight
--   3. How Cortex Code connects Git + Snowflake
--   4. Why version-controlled SQL is better than file shares
