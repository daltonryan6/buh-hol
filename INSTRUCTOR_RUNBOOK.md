# Instructor Runbook - BUH Hands-On Lab

## Pre-Session Checklist

- [ ] Snowflake trial or existing account accessible for all attendees
- [ ] Each attendee has ACCOUNTADMIN or equivalent privileges
- [ ] Repository accessible (GitHub link shared, or scripts downloaded)
- [ ] Test run: execute 00_setup.sql through 06 end-to-end in a clean account
- [ ] Screen share and projection ready
- [ ] For Power BI/Iceberg walkthrough: have screenshots or a pre-built demo ready if you want to show the Fabric side (not required for trial accounts)

## Timing Guide

| Time | Module | Script | Mode | Facilitator Notes |
|------|--------|--------|------|-------------------|
| 0:00-0:10 | Welcome + Setup | 00_setup.sql | Hands-on | Everyone runs setup together. Verify 5 tables: PATIENT(15), PAT_ENC(25), CLARITY_SER(8), ORDER_PROC(28), HSP_ACCT_DX_LIST(30). |
| 0:10-0:25 | Git Workspaces | 01_workspaces_and_git.sql | Hands-on | Instructor creates API integration. Everyone connects repo, browses files, runs EXECUTE IMMEDIATE FROM repo. |
| 0:25-1:05 | Dynamic Tables | 02_dynamic_tables.sql | Hands-on | The centerpiece. Build 5 CURATED + 3 GOLD dynamic tables. Insert new patient P100016 (Jorge Medina, ED stroke) and watch cascade. Monitor refresh history. |
| 1:05-1:20 | Power BI / Iceberg / Fabric | 03_powerbi_iceberg_fabric.sql | Walkthrough | 3-option PBI comparison, one Iceberg CTAS, Fabric CU warning, recommended hybrid pattern. Iceberg CTAS may fail on some trial editions - have fallback discussion ready. |
| 1:20-1:40 | Tags + Governance | 04_tags_and_governance.sql | Walkthrough + demo | Create tags, apply to INBOUND.PATIENT columns (Clarity names: PAT_MRN_ID, EMAIL_ADDRESS, HOME_PHONE, etc.), tag-based masking, test with POLICY_CONTEXT across 3 roles. |
| 1:40-1:55 | Putting it together | 05_putting_it_together.sql | Discussion | Architecture diagram, end-to-end verification, next steps for their environment. |
| 1:55-2:00 | Recap | 06_cleanup.sql | Wrap-up | Summarize key takeaways. Offer cleanup script. |

## Common Issues and Fallbacks

| Issue | Fix |
|-------|-----|
| "Warehouse does not exist" | Setup script creates COMPUTE_WH. If it fails, the user may not have ACCOUNTADMIN. |
| EXECUTE IMMEDIATE FROM repo fails | The setup script drops and recreates BUH_HOL, which destroys the repo object. Run 00_setup.sql manually from the worksheet instead. |
| Dynamic table shows 0 rows | DTs may take up to TARGET_LAG to populate. Wait 1 minute and re-query. Check `INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY()` for errors. |
| Iceberg CTAS fails with "external volume" error | Managed Iceberg (CATALOG='SNOWFLAKE' with empty EXTERNAL_VOLUME) may require specific account settings. Fall back to walkthrough discussion. |
| TAG_REFERENCES returns 0 rows | ACCOUNT_USAGE views have latency (up to 2 hours). Use `INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS()` for real-time results. |
| POLICY_CONTEXT not available | Create test users: `CREATE USER lab_analyst_test PASSWORD='Test1234!' DEFAULT_ROLE=BUH_LAB_ANALYST; GRANT ROLE BUH_LAB_ANALYST TO USER lab_analyst_test;` and log in as that user. |
| Tag-based masking policy conflict | SSN and DOB have direct policies (different masking behavior). Other PII columns use the tag-based policy. This is by design - you cannot have both on the same column. |

## Key Discussion Points by Module

### Git Workspaces
- "How does your team share SQL today?" (usually Slack, email, shared drives)
- Git workspaces replace that with versioned, reviewable, deployable code
- For Snowforge: Git workspaces + dynamic tables = version-controlled declarative pipelines

### Dynamic Tables
- "How many Snowforge scripts do you maintain today?"
- Dynamic tables replace orchestration complexity with declarative SQL
- TARGET_LAG is the key design decision - not "when to run" but "how fresh"
- Louis reported: DTs used similar credits but saved significant engineering time
- The value is not cheaper compute - it is the monitoring, retry, and scheduling code you delete

### Power BI / Iceberg / Fabric
- "Microsoft is recommending Iceberg for your gold layer" - this is the right pattern
- Cost play: keep pipeline in Snowflake (where you have expertise), expose only GOLD as Iceberg
- Fabric CU overconsumption happens when you run too many workloads on undersized capacity
- Purview can scan Snowflake directly - tags and labels are separate systems that need alignment

### Tags and Governance
- Tags are metadata that DESCRIBE what data is; masking ENFORCES policy based on tags
- Tag-based masking: one policy protects all columns with that tag - no per-column setup
- SYSTEM$CLASSIFY automates PII detection so you do not tag 500 Clarity columns by hand
- For BUH: tags + classification + masking is the foundation; Purview alignment is a follow-on project

## Data Design Notes

The synthetic data is designed for realistic clinical scenarios:
- **Maria Santos (P100001)**: 3 cardiology visits (STEMI + follow-ups) - shows repeat visit pattern
- **James Okafor (P100002)**: Progressive CKD (creatinine rising across encounters) - shows disease progression
- **Thomas Murphy (P100012)**: Heart failure inpatient + ED return within 18 days - flags in READMISSION_RISK
- **Jorge Medina (P100016)**: Inserted during DT demo - ED stroke patient, cascades through all layers
- All addresses are Providence RI. ICD-10 codes and Clarity column conventions are authentic.

## Teardown

After the session, each attendee runs `scripts/06_cleanup.sql`. Important: unset the warehouse tag before dropping the database, or the tag reference will be orphaned.
