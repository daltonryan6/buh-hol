# Brown University Health - Hands-On Lab

## Snowflake Workspaces, Dynamic Tables, Power BI/Iceberg & Governance - in 2 Hours

### Overview

This lab covers the topics Louis's team at Brown University Health is evaluating: Git-based shared workspaces, dynamic table pipelines, Power BI and Iceberg connectivity (including Fabric cost considerations and Purview), and Snowflake tags with sensitivity labels and masking.

### What you will learn

1. **Shared Workspaces** - How to connect Git to Snowflake, browse and run versioned SQL, and collaborate
2. **Dynamic Tables** - Replace scheduled ETL with declarative, auto-refreshing pipelines across RAW, CURATED, and GOLD layers
3. **Power BI, Iceberg & Fabric** - Connection options, Iceberg for your gold/datamart layer, Fabric cost drivers, and Purview integration
4. **Tags & Governance** - Where tags apply, sensitivity labels, tag-based masking, and how Snowflake tags relate to Purview labels

### Prerequisites

1. **Snowflake account** - Sign up for a free trial at [signup.snowflake.com](https://signup.snowflake.com/) (Enterprise edition, any cloud/region) or use an existing account
2. Log in with the **ACCOUNTADMIN** role
3. The setup script creates everything needed - no pre-configuration required

### Quick start

1. Clone this repository or download the `scripts/` folder
2. Open `scripts/00_setup.sql` and run it end-to-end
3. Follow the guided website at [daltonryan6.github.io/buh-hol](https://daltonryan6.github.io/buh-hol/) or work through the numbered scripts in order

### Session flow (120 minutes)

| Time | Module | Script |
|------|--------|--------|
| 0-10 | Welcome and setup | `00_setup.sql` |
| 10-25 | Shared Workspaces and Git | `01_workspaces_and_git.sql` |
| 25-55 | Dynamic Tables | `02_dynamic_tables.sql` |
| 55-80 | Power BI, Iceberg and Fabric | `03_powerbi_iceberg_fabric.sql` |
| 80-105 | Tags, Sensitivity Labels and Governance | `04_tags_and_governance.sql` |
| 105-115 | Bringing it together | `05_putting_it_together.sql` |
| 115-120 | Recap and cleanup | `06_cleanup.sql` |

### Repository structure

```
buh-hol/
  index.html                         -- Guided walkthrough website
  assets/
    styles.css                       -- Site styling
    lab.js                           -- Navigation, copy, dark mode
  scripts/
    00_setup.sql                     -- Database, schemas, roles, synthetic data
    01_workspaces_and_git.sql        -- Git integration walkthrough
    02_dynamic_tables.sql            -- Dynamic table pipeline (hands-on)
    03_powerbi_iceberg_fabric.sql    -- Power BI/Iceberg/Fabric walkthrough
    04_tags_and_governance.sql       -- Tags and masking (hands-on)
    05_putting_it_together.sql       -- End-to-end verification
    06_cleanup.sql                   -- Tear down lab objects
  INSTRUCTOR_RUNBOOK.md              -- Timing, fallbacks, privilege checklist
```

### Cleanup

Run `scripts/06_cleanup.sql` to drop the lab database and roles when finished.
