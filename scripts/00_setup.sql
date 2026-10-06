/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 00: Setup - Database, Schemas, Roles, Epic Clarity Source Data

  PREREQUISITES:
    - Snowflake trial or existing account with ACCOUNTADMIN
    - No pre-configuration needed - this script creates everything

  WHAT THIS CREATES:
    - Database:  BUH_HOL
    - Schemas:   INBOUND, CURATED, GOLD, GOVERNANCE
    - Roles:     BUH_LAB_ADMIN, BUH_LAB_ANALYST, BUH_LAB_CLINICIAN
    - Tables:    Epic Clarity-style source tables with synthetic clinical
                 data for dynamic table pipelines and governance demos

  NOTE: INBOUND tables use Epic Clarity naming conventions. These mirror
        the tables that Snowlift/Snowloader stages from your SQL Server
        Clarity database today.

  SAFE TO RERUN: Yes - uses CREATE OR REPLACE throughout
=============================================================================*/

-- ============================================================
-- 0. ENVIRONMENT
-- ============================================================
USE ROLE ACCOUNTADMIN;
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================
-- 1. DATABASE AND SCHEMAS
-- ============================================================
CREATE OR REPLACE DATABASE BUH_HOL;

CREATE SCHEMA BUH_HOL.INBOUND;     -- Bronze: raw Clarity extracts land here
CREATE SCHEMA BUH_HOL.CURATED;     -- Silver: cleaned dimensional model
CREATE SCHEMA BUH_HOL.GOLD;        -- Gold: aggregated reporting tables
CREATE SCHEMA BUH_HOL.GOVERNANCE;  -- Tags, masking policies

-- ============================================================
-- 2. LAB ROLES
-- ============================================================
CREATE ROLE IF NOT EXISTS BUH_LAB_ADMIN;
CREATE ROLE IF NOT EXISTS BUH_LAB_ANALYST;
CREATE ROLE IF NOT EXISTS BUH_LAB_CLINICIAN;

GRANT ROLE BUH_LAB_ADMIN TO ROLE ACCOUNTADMIN;
GRANT ROLE BUH_LAB_ANALYST TO ROLE BUH_LAB_ADMIN;
GRANT ROLE BUH_LAB_CLINICIAN TO ROLE BUH_LAB_ADMIN;

GRANT USAGE ON DATABASE BUH_HOL TO ROLE BUH_LAB_ADMIN;
GRANT USAGE ON DATABASE BUH_HOL TO ROLE BUH_LAB_ANALYST;
GRANT USAGE ON DATABASE BUH_HOL TO ROLE BUH_LAB_CLINICIAN;

GRANT ALL ON ALL SCHEMAS IN DATABASE BUH_HOL TO ROLE BUH_LAB_ADMIN;
GRANT USAGE ON ALL SCHEMAS IN DATABASE BUH_HOL TO ROLE BUH_LAB_ANALYST;
GRANT USAGE ON ALL SCHEMAS IN DATABASE BUH_HOL TO ROLE BUH_LAB_CLINICIAN;

GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE BUH_LAB_ADMIN;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE BUH_LAB_ANALYST;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE BUH_LAB_CLINICIAN;

GRANT SELECT ON FUTURE TABLES IN DATABASE BUH_HOL TO ROLE BUH_LAB_ANALYST;
GRANT SELECT ON FUTURE TABLES IN DATABASE BUH_HOL TO ROLE BUH_LAB_CLINICIAN;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN DATABASE BUH_HOL TO ROLE BUH_LAB_ANALYST;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN DATABASE BUH_HOL TO ROLE BUH_LAB_CLINICIAN;
GRANT SELECT ON FUTURE VIEWS IN DATABASE BUH_HOL TO ROLE BUH_LAB_ANALYST;
GRANT SELECT ON FUTURE VIEWS IN DATABASE BUH_HOL TO ROLE BUH_LAB_CLINICIAN;

-- ============================================================
-- 3. INBOUND LAYER - Simulated Epic Clarity Extracts
--    These use Clarity naming conventions. In production,
--    Snowlift/Snowloader would stage these from SQL Server.
-- ============================================================
USE SCHEMA BUH_HOL.INBOUND;

-- -----------------------------------------------
-- 3a. PATIENT - Epic Clarity patient demographics
-- -----------------------------------------------
CREATE OR REPLACE TABLE PATIENT (
    PAT_ID          VARCHAR(20)  NOT NULL,
    PAT_MRN_ID      VARCHAR(15)  NOT NULL,
    PAT_FIRST_NAME  VARCHAR(50),
    PAT_LAST_NAME   VARCHAR(50),
    BIRTH_DATE      DATE,
    SSN             VARCHAR(11),
    ADD_LINE_1      VARCHAR(100),
    CITY            VARCHAR(50),
    STATE_ABBR      VARCHAR(2),
    ZIP             VARCHAR(10),
    HOME_PHONE      VARCHAR(15),
    EMAIL_ADDRESS   VARCHAR(100),
    LANGUAGE        VARCHAR(30),
    SEX             VARCHAR(10),
    LOAD_TS         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO PATIENT (PAT_ID,PAT_MRN_ID,PAT_FIRST_NAME,PAT_LAST_NAME,BIRTH_DATE,SSN,ADD_LINE_1,CITY,STATE_ABBR,ZIP,HOME_PHONE,EMAIL_ADDRESS,LANGUAGE,SEX) VALUES
('P100001','MRN-900001','maria','santos','1965-03-14','111-22-3333','100 Hope St','Providence','RI','02906','4015550101','msantos@example.com','English','Female'),
('P100002','MRN-900002','james','okafor','1978-11-02','222-33-4444','45 Thayer St','Providence','RI','02912','4015550102','jokafor@example.com','English','Male'),
('P100003','MRN-900003','lin','chen','1990-07-21','333-44-5555','200 Wickenden St','Providence','RI','02903','4015550103','lchen@example.com','Mandarin','Female'),
('P100004','MRN-900004','robert','williams','1955-01-30','444-55-6666','88 Broad St','Providence','RI','02903','4015550104','rwilliams@example.com','English','Male'),
('P100005','MRN-900005','fatima','al-hassan','1988-09-15','555-66-7777','12 Benefit St','Providence','RI','02904','4015550105','falhassan@example.com','Arabic','Female'),
('P100006','MRN-900006','david','park','1972-04-08','666-77-8888','300 Brook St','Providence','RI','02906','4015550106','dpark@example.com','English','Male'),
('P100007','MRN-900007','sarah','johnson','1983-12-25','777-88-9999','55 Power St','Providence','RI','02906','4015550107','sjohnson@example.com','English','Female'),
('P100008','MRN-900008','carlos','rivera','1995-06-10','888-99-0000','400 Hope St','Providence','RI','02906','4015550108','crivera@example.com','Spanish','Male'),
('P100009','MRN-900009','elena','vasquez','2001-02-14','999-00-1111','500 Atwells Ave','Providence','RI','02909','4015550109','evasquez@example.com','Spanish','Female'),
('P100010','MRN-900010','michael','thompson','1960-08-22','123-45-6789','75 Waterman St','Providence','RI','02906','4015550110','mthompson@example.com','English','Male'),
('P100011','MRN-900011','priya','sharma','1985-04-17','234-56-7890','160 Angell St','Providence','RI','02906','4015550111','psharma@example.com','Hindi','Female'),
('P100012','MRN-900012','thomas','murphy','1948-12-03','345-67-8901','22 Elmgrove Ave','Providence','RI','02906','4015550112','tmurphy@example.com','English','Male'),
('P100013','MRN-900013','anh','nguyen','1992-06-30','456-78-9012','310 Broadway','Providence','RI','02903','4015550113','anguyen@example.com','Vietnamese','Female'),
('P100014','MRN-900014','william','brown','1970-09-18','567-89-0123','45 Doyle Ave','Providence','RI','02906','4015550114','wbrown@example.com','English','Male'),
('P100015','MRN-900015','sofia','garcia','1998-01-25','678-90-1234','88 Transit St','Providence','RI','02906','4015550115','sgarcia@example.com','Spanish','Female');

-- -----------------------------------------------
-- 3b. PAT_ENC - Epic Clarity patient encounters
-- -----------------------------------------------
CREATE OR REPLACE TABLE PAT_ENC (
    PAT_ENC_CSN_ID     VARCHAR(20)  NOT NULL,
    PAT_ID             VARCHAR(20)  NOT NULL,
    ENC_TYPE_C         NUMBER(2),        -- 1=Inpatient, 2=Outpatient, 3=Emergency, 4=Observation
    CONTACT_DATE       DATE,
    HOSP_ADMSN_TIME    TIMESTAMP_NTZ,
    HOSP_DISCH_TIME    TIMESTAMP_NTZ,
    DEPARTMENT_ID      NUMBER(10),
    DEPARTMENT_NAME    VARCHAR(50),
    VISIT_PROV_ID      VARCHAR(20),
    ACCT_BASECLS_HA    NUMBER(12,2),     -- total charges
    ENC_CLOSED_YN      VARCHAR(1),
    LOAD_TS            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO PAT_ENC (PAT_ENC_CSN_ID,PAT_ID,ENC_TYPE_C,CONTACT_DATE,HOSP_ADMSN_TIME,HOSP_DISCH_TIME,DEPARTMENT_ID,DEPARTMENT_NAME,VISIT_PROV_ID,ACCT_BASECLS_HA,ENC_CLOSED_YN) VALUES
('E200001','P100001',1,'2024-08-10','2024-08-10 08:15:00','2024-08-14 11:00:00',1001,'Cardiology','PROV-001',45200.00,'Y'),
('E200002','P100002',2,'2024-09-01','2024-09-01 09:30:00',NULL,1002,'Primary Care','PROV-002',350.00,'Y'),
('E200003','P100003',3,'2024-09-15','2024-09-15 02:45:00','2024-09-15 08:30:00',1003,'Emergency Department','PROV-003',8900.00,'Y'),
('E200004','P100004',1,'2024-09-20','2024-09-20 10:00:00','2024-09-28 14:00:00',1004,'Oncology','PROV-004',72500.00,'Y'),
('E200005','P100001',2,'2024-10-01','2024-10-01 10:00:00',NULL,1001,'Cardiology','PROV-001',275.00,'Y'),
('E200006','P100005',2,'2024-10-05','2024-10-05 11:00:00',NULL,1005,'OB/GYN','PROV-005',425.00,'Y'),
('E200007','P100006',1,'2024-10-10','2024-10-10 07:00:00','2024-10-12 10:30:00',1006,'Orthopedics','PROV-006',38900.00,'Y'),
('E200008','P100007',3,'2024-10-12','2024-10-12 19:20:00','2024-10-12 23:45:00',1003,'Emergency Department','PROV-003',2100.00,'Y'),
('E200009','P100008',2,'2024-10-15','2024-10-15 14:00:00',NULL,1007,'Behavioral Health','PROV-007',310.00,'Y'),
('E200010','P100002',1,'2024-10-18','2024-10-18 06:30:00','2024-10-22 11:00:00',1008,'Nephrology','PROV-008',28700.00,'Y'),
('E200011','P100010',3,'2024-10-20','2024-10-20 03:15:00','2024-10-20 09:00:00',1003,'Emergency Department','PROV-003',4500.00,'Y'),
('E200012','P100011',2,'2024-10-22','2024-10-22 09:00:00',NULL,1005,'OB/GYN','PROV-005',525.00,'Y'),
('E200013','P100012',1,'2024-10-25','2024-10-25 12:00:00','2024-11-01 10:00:00',1001,'Cardiology','PROV-001',58300.00,'Y'),
('E200014','P100013',3,'2024-10-28','2024-10-28 22:10:00','2024-10-29 04:30:00',1003,'Emergency Department','PROV-003',3800.00,'Y'),
('E200015','P100014',2,'2024-11-01','2024-11-01 08:30:00',NULL,1002,'Primary Care','PROV-002',280.00,'Y'),
('E200016','P100015',3,'2024-11-03','2024-11-03 15:45:00','2024-11-03 21:00:00',1003,'Emergency Department','PROV-003',5200.00,'Y'),
('E200017','P100001',2,'2024-11-05','2024-11-05 10:00:00',NULL,1001,'Cardiology','PROV-001',275.00,'Y'),
('E200018','P100010',1,'2024-11-08','2024-11-08 09:00:00','2024-11-11 14:00:00',1001,'Cardiology','PROV-001',32100.00,'Y'),
('E200019','P100003',3,'2024-11-10','2024-11-10 01:30:00','2024-11-10 06:00:00',1003,'Emergency Department','PROV-003',3100.00,'Y'),
('E200020','P100012',3,'2024-11-12','2024-11-12 18:00:00','2024-11-13 02:00:00',1003,'Emergency Department','PROV-008',6700.00,'Y'),
('E200021','P100002',2,'2024-11-15','2024-11-15 09:00:00',NULL,1008,'Nephrology','PROV-008',420.00,'Y'),
('E200022','P100009',3,'2024-11-18','2024-11-18 04:00:00','2024-11-18 10:30:00',1003,'Emergency Department','PROV-003',4100.00,'Y'),
('E200023','P100004',2,'2024-11-20','2024-11-20 11:00:00',NULL,1004,'Oncology','PROV-004',850.00,'Y'),
('E200024','P100006',2,'2024-11-22','2024-11-22 08:00:00',NULL,1006,'Orthopedics','PROV-006',375.00,'Y'),
('E200025','P100011',2,'2024-11-25','2024-11-25 10:30:00',NULL,1005,'OB/GYN','PROV-005',625.00,'Y');

-- -----------------------------------------------
-- 3c. CLARITY_SER - Epic provider (service employee)
-- -----------------------------------------------
CREATE OR REPLACE TABLE CLARITY_SER (
    PROV_ID        VARCHAR(20) NOT NULL,
    PROV_NAME      VARCHAR(100),
    SPECIALTY      VARCHAR(50),
    DEPARTMENT     VARCHAR(50),
    NPI            VARCHAR(10),
    ACTIVE_STATUS  VARCHAR(1)    -- Y/N
);

INSERT INTO CLARITY_SER VALUES
('PROV-001','Dr. Amy Chen','Cardiology','Cardiology','1234567890','Y'),
('PROV-002','Dr. Marcus Brown','Internal Medicine','Primary Care','2345678901','Y'),
('PROV-003','Dr. Lisa Park','Emergency Medicine','Emergency Department','3456789012','Y'),
('PROV-004','Dr. James Wright','Oncology','Oncology','4567890123','Y'),
('PROV-005','Dr. Sarah Kim','OB/GYN','OB/GYN','5678901234','Y'),
('PROV-006','Dr. David Lee','Orthopedic Surgery','Orthopedics','6789012345','Y'),
('PROV-007','Dr. Nina Patel','Psychiatry','Behavioral Health','7890123456','Y'),
('PROV-008','Dr. Robert Garcia','Nephrology','Nephrology','8901234567','Y');

-- -----------------------------------------------
-- 3d. ORDER_PROC - Epic lab/procedure orders
-- -----------------------------------------------
CREATE OR REPLACE TABLE ORDER_PROC (
    ORDER_PROC_ID    VARCHAR(20) NOT NULL,
    PAT_ENC_CSN_ID   VARCHAR(20) NOT NULL,
    PAT_ID           VARCHAR(20) NOT NULL,
    PROC_CODE        VARCHAR(20),
    DESCRIPTION      VARCHAR(200),
    ORD_VALUE        NUMBER(10,2),
    RESULT_UNIT      VARCHAR(20),
    REFERENCE_LOW    NUMBER(10,2),
    REFERENCE_HIGH   NUMBER(10,2),
    RESULT_FLAG_C    NUMBER(1),         -- 0=Normal, 1=Abnormal High, 2=Abnormal Low
    RESULT_DATE      TIMESTAMP_NTZ,
    LOAD_TS          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO ORDER_PROC (ORDER_PROC_ID,PAT_ENC_CSN_ID,PAT_ID,PROC_CODE,DESCRIPTION,ORD_VALUE,RESULT_UNIT,REFERENCE_LOW,REFERENCE_HIGH,RESULT_FLAG_C,RESULT_DATE) VALUES
('OP001','E200001','P100001','TROP','Troponin I',2.45,'ng/mL',0.00,0.04,1,'2024-08-10 06:30:00'),
('OP002','E200001','P100001','BNP','B-type Natriuretic Peptide',890.00,'pg/mL',0.00,100.00,1,'2024-08-10 06:30:00'),
('OP003','E200002','P100002','HBA1C','Hemoglobin A1c',8.20,'%',4.00,5.60,1,'2024-09-01 09:00:00'),
('OP004','E200004','P100004','WBC','White Blood Cell Count',3.10,'K/uL',4.50,11.00,2,'2024-09-20 07:00:00'),
('OP005','E200010','P100002','CREAT','Creatinine',4.20,'mg/dL',0.70,1.30,1,'2024-10-18 08:00:00'),
('OP006','E200010','P100002','GFR','Estimated GFR',22.00,'mL/min',90.00,120.00,2,'2024-10-18 08:00:00'),
('OP007','E200001','P100001','CHOL','Total Cholesterol',245.00,'mg/dL',0.00,200.00,1,'2024-08-10 06:30:00'),
('OP008','E200001','P100001','LDL','LDL Cholesterol',165.00,'mg/dL',0.00,100.00,1,'2024-08-10 06:30:00'),
('OP009','E200005','P100001','TROP','Troponin I',0.02,'ng/mL',0.00,0.04,0,'2024-10-01 10:00:00'),
('OP010','E200005','P100001','BNP','B-type Natriuretic Peptide',85.00,'pg/mL',0.00,100.00,0,'2024-10-01 10:00:00'),
('OP011','E200003','P100003','CBC','Complete Blood Count',7.20,'K/uL',4.50,11.00,0,'2024-09-15 03:00:00'),
('OP012','E200008','P100007','FLU','Influenza A/B PCR',1.00,'pos/neg',0.00,0.00,1,'2024-10-12 20:00:00'),
('OP013','E200010','P100002','K','Potassium',5.80,'mEq/L',3.50,5.00,1,'2024-10-18 08:00:00'),
('OP014','E200011','P100010','TROP','Troponin I',0.08,'ng/mL',0.00,0.04,1,'2024-10-20 03:30:00'),
('OP015','E200011','P100010','ECG','Electrocardiogram',NULL,NULL,NULL,NULL,0,'2024-10-20 03:45:00'),
('OP016','E200013','P100012','TROP','Troponin I',3.10,'ng/mL',0.00,0.04,1,'2024-10-25 12:30:00'),
('OP017','E200013','P100012','BNP','B-type Natriuretic Peptide',1250.00,'pg/mL',0.00,100.00,1,'2024-10-25 12:30:00'),
('OP018','E200014','P100013','UATOX','Urine Drug Screen',NULL,NULL,NULL,NULL,0,'2024-10-28 22:30:00'),
('OP019','E200016','P100015','HCG','Beta-hCG Quantitative',15000.00,'mIU/mL',NULL,NULL,0,'2024-11-03 16:00:00'),
('OP020','E200018','P100010','TROP','Troponin I',0.01,'ng/mL',0.00,0.04,0,'2024-11-08 09:30:00'),
('OP021','E200018','P100010','BNP','B-type Natriuretic Peptide',210.00,'pg/mL',0.00,100.00,1,'2024-11-08 09:30:00'),
('OP022','E200019','P100003','XRAY','X-Ray Left Wrist',NULL,NULL,NULL,NULL,0,'2024-11-10 02:00:00'),
('OP023','E200020','P100012','TROP','Troponin I',0.85,'ng/mL',0.00,0.04,1,'2024-11-12 18:30:00'),
('OP024','E200020','P100012','BNP','B-type Natriuretic Peptide',980.00,'pg/mL',0.00,100.00,1,'2024-11-12 18:30:00'),
('OP025','E200021','P100002','CREAT','Creatinine',4.50,'mg/dL',0.70,1.30,1,'2024-11-15 09:30:00'),
('OP026','E200022','P100009','CBC','Complete Blood Count',6.80,'K/uL',4.50,11.00,0,'2024-11-18 04:30:00'),
('OP027','E200022','P100009','BMP','Basic Metabolic Panel',NULL,NULL,NULL,NULL,0,'2024-11-18 04:30:00'),
('OP028','E200023','P100004','WBC','White Blood Cell Count',2.80,'K/uL',4.50,11.00,2,'2024-11-20 11:30:00');

-- -----------------------------------------------
-- 3e. HSP_ACCT_DX_LIST - Diagnosis codes per encounter
-- -----------------------------------------------
CREATE OR REPLACE TABLE HSP_ACCT_DX_LIST (
    PAT_ENC_CSN_ID  VARCHAR(20) NOT NULL,
    LINE            NUMBER(3),
    DX_ID           VARCHAR(20),
    ICD10_CODE      VARCHAR(10),
    DX_NAME         VARCHAR(200)
);

INSERT INTO HSP_ACCT_DX_LIST VALUES
('E200001',1,'DX001','I21.0','ST elevation myocardial infarction involving left main coronary artery'),
('E200001',2,'DX002','I25.10','Atherosclerotic heart disease of native coronary artery'),
('E200002',1,'DX003','E11.9','Type 2 diabetes mellitus without complications'),
('E200003',1,'DX004','S52.501A','Unspecified fracture of lower end of left radius'),
('E200004',1,'DX005','C34.90','Malignant neoplasm of unspecified part of unspecified bronchus or lung'),
('E200005',1,'DX006','I21.0','ST elevation MI - follow-up'),
('E200006',1,'DX007','Z34.00','Encounter for supervision of normal first pregnancy'),
('E200007',1,'DX008','M17.11','Primary osteoarthritis right knee'),
('E200008',1,'DX009','J06.9','Acute upper respiratory infection unspecified'),
('E200009',1,'DX010','F32.1','Major depressive disorder single episode moderate'),
('E200010',1,'DX011','N18.4','Chronic kidney disease stage 4'),
('E200010',2,'DX012','E11.22','Type 2 diabetes mellitus with diabetic chronic kidney disease'),
('E200011',1,'DX013','R07.9','Chest pain unspecified'),
('E200011',2,'DX014','I20.9','Angina pectoris unspecified'),
('E200012',1,'DX015','Z34.00','Encounter for supervision of normal first pregnancy'),
('E200013',1,'DX016','I50.9','Heart failure unspecified'),
('E200013',2,'DX017','I25.10','Atherosclerotic heart disease of native coronary artery'),
('E200014',1,'DX018','R10.9','Unspecified abdominal pain'),
('E200015',1,'DX019','Z00.00','Encounter for general adult medical examination'),
('E200016',1,'DX020','O20.0','Threatened abortion'),
('E200017',1,'DX021','I21.0','ST elevation MI - cardiac rehab follow-up'),
('E200018',1,'DX022','I50.9','Heart failure unspecified'),
('E200018',2,'DX023','I20.9','Angina pectoris unspecified'),
('E200019',1,'DX024','S62.001A','Unspecified fracture of navicular bone of left wrist'),
('E200020',1,'DX025','I50.9','Heart failure unspecified - acute exacerbation'),
('E200021',1,'DX026','N18.4','Chronic kidney disease stage 4 - follow-up'),
('E200022',1,'DX027','R10.9','Unspecified abdominal pain'),
('E200023',1,'DX028','C34.90','Malignant neoplasm of lung - surveillance'),
('E200024',1,'DX029','M17.11','Primary osteoarthritis right knee - post-op follow-up'),
('E200025',1,'DX030','Z34.00','Encounter for supervision of normal first pregnancy - 28 week');

-- ============================================================
-- 4. CHECKPOINT: Verify setup
-- ============================================================
SELECT 'PATIENT' AS TBL, COUNT(*) AS ROWS FROM BUH_HOL.INBOUND.PATIENT
UNION ALL SELECT 'PAT_ENC', COUNT(*) FROM BUH_HOL.INBOUND.PAT_ENC
UNION ALL SELECT 'CLARITY_SER', COUNT(*) FROM BUH_HOL.INBOUND.CLARITY_SER
UNION ALL SELECT 'ORDER_PROC', COUNT(*) FROM BUH_HOL.INBOUND.ORDER_PROC
UNION ALL SELECT 'HSP_ACCT_DX_LIST', COUNT(*) FROM BUH_HOL.INBOUND.HSP_ACCT_DX_LIST
ORDER BY TBL;

/*
  EXPECTED OUTPUT:
  CLARITY_SER        8
  HSP_ACCT_DX_LIST  30
  ORDER_PROC        28
  PAT_ENC           25
  PATIENT           15
*/
