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

  DATA VOLUMES:
    - PATIENT:           100 hand-crafted rows
    - PAT_ENC:         7,500 generated encounters (5 yrs of history)
    - CLARITY_SER:        20 hand-crafted providers
    - ORDER_PROC:     75,000 generated lab orders
    - HSP_ACCT_DX_LIST:22,500 generated diagnoses

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
--     100 hand-crafted rows with realistic RI data
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
-- Original 15 patients
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
('P100015','MRN-900015','sofia','garcia','1998-01-25','678-90-1234','88 Transit St','Providence','RI','02906','4015550115','sgarcia@example.com','Spanish','Female'),
-- Patients 16-30
('P100016','MRN-900016','jennifer','martinez','1977-05-09','789-01-2345','15 Governor St','Providence','RI','02906','4015550116','jmartinez@example.com','English','Female'),
('P100017','MRN-900017','kevin','oconnell','1962-10-31','890-12-3456','220 Ives St','Providence','RI','02906','4015550117','koconnell@example.com','English','Male'),
('P100018','MRN-900018','mei','liu','1994-08-12','901-23-4567','33 Prospect St','Providence','RI','02906','4015550118','mliu@example.com','Mandarin','Female'),
('P100019','MRN-900019','daniel','sullivan','1980-02-28','012-34-5678','410 Smith St','Providence','RI','02908','4015550119','dsullivan@example.com','English','Male'),
('P100020','MRN-900020','rosa','pereira','1971-12-17','102-35-6789','55 Federal Hill','Providence','RI','02903','4015550120','rpereira@example.com','Portuguese','Female'),
('P100021','MRN-900021','brian','kelly','1956-07-04','203-46-7890','180 Wayland Ave','Providence','RI','02906','4015550121','bkelly@example.com','English','Male'),
('P100022','MRN-900022','yuki','tanaka','1989-03-30','304-57-8901','92 Pitman St','Providence','RI','02906','4015550122','ytanaka@example.com','English','Female'),
('P100023','MRN-900023','marcus','jackson','1967-08-19','405-68-9012','340 Prairie Ave','Providence','RI','02905','4015550123','mjackson@example.com','English','Male'),
('P100024','MRN-900024','ana','ferreira','2003-01-05','506-79-0123','28 Knight St','Providence','RI','02909','4015550124','aferreira@example.com','Portuguese','Female'),
('P100025','MRN-900025','steven','wilson','1953-11-11','607-80-1234','150 Camp St','Providence','RI','02906','4015550125','swilson@example.com','English','Male'),
('P100026','MRN-900026','lucia','dominguez','1986-06-22','708-91-2345','67 Congress Ave','Providence','RI','02907','4015550126','ldominguez@example.com','Spanish','Female'),
('P100027','MRN-900027','patrick','walsh','1974-04-15','809-02-3456','200 Blackstone Blvd','Providence','RI','02906','4015550127','pwalsh@example.com','English','Male'),
('P100028','MRN-900028','hana','kim','1991-09-08','910-13-4567','44 Rochambeau Ave','Providence','RI','02906','4015550128','hkim@example.com','English','Female'),
('P100029','MRN-900029','anthony','costa','1958-03-21','011-24-5678','380 Cranston St','Providence','RI','02907','4015550129','acosta@example.com','Portuguese','Male'),
('P100030','MRN-900030','rachel','anderson','1996-12-02','112-35-6780','60 Medway St','Providence','RI','02906','4015550130','randerson@example.com','English','Female'),
-- Patients 31-50
('P100031','MRN-900031','omar','hassan','1982-07-14','213-46-7891','125 Broad St','Providence','RI','02903','4015550131','ohassan@example.com','Arabic','Male'),
('P100032','MRN-900032','christine','taylor','1969-01-27','314-57-8902','88 Taber Ave','Providence','RI','02906','4015550132','ctaylor@example.com','English','Female'),
('P100033','MRN-900033','jose','morales','1993-05-16','415-68-9013','210 Manton Ave','Providence','RI','02909','4015550133','jmorales@example.com','Spanish','Male'),
('P100034','MRN-900034','samantha','lee','1987-10-03','516-79-0124','72 Lloyd Ave','Providence','RI','02906','4015550134','slee@example.com','English','Female'),
('P100035','MRN-900035','richard','flynn','1950-06-30','617-80-1235','305 Olney St','Providence','RI','02906','4015550135','rflynn@example.com','English','Male'),
('P100036','MRN-900036','diana','reyes','1999-04-18','718-91-2346','48 Cypress St','Providence','RI','02906','4015550136','dreyes@example.com','Spanish','Female'),
('P100037','MRN-900037','kenneth','moore','1964-11-25','819-02-3457','190 Gano St','Providence','RI','02906','4015550137','kmoore@example.com','English','Male'),
('P100038','MRN-900038','linh','tran','1988-02-09','920-13-4568','27 Arnold St','Providence','RI','02906','4015550138','ltran@example.com','Vietnamese','Female'),
('P100039','MRN-900039','edward','burke','1975-08-06','021-24-5679','410 Eaton St','Providence','RI','02908','4015550139','eburke@example.com','English','Male'),
('P100040','MRN-900040','gabriela','silva','2000-03-29','122-35-6781','95 Pocasset Ave','Providence','RI','02909','4015550140','gsilva@example.com','Portuguese','Female'),
('P100041','MRN-900041','frank','russo','1957-09-13','223-46-7892','300 Atwells Ave','Providence','RI','02903','4015550141','frusso@example.com','English','Male'),
('P100042','MRN-900042','amira','ibrahim','1984-07-20','324-57-8903','60 Elton St','Providence','RI','02906','4015550142','aibrahim@example.com','Arabic','Female'),
('P100043','MRN-900043','jason','campbell','1971-12-08','425-68-9014','14 University Ave','Providence','RI','02906','4015550143','jcampbell@example.com','English','Male'),
('P100044','MRN-900044','marta','almeida','1990-01-14','526-79-0125','230 Dean St','Providence','RI','02903','4015550144','malmeida@example.com','Portuguese','Female'),
('P100045','MRN-900045','george','harris','1946-05-22','627-80-1236','80 Slater Ave','Providence','RI','02906','4015550145','gharris@example.com','English','Male'),
('P100046','MRN-900046','nina','petrova','1983-08-31','728-91-2347','155 Ives St','Providence','RI','02906','4015550146','npetrova@example.com','English','Female'),
('P100047','MRN-900047','raymond','diaz','1968-04-02','829-02-3458','42 Whitmarsh St','Providence','RI','02907','4015550147','rdiaz@example.com','Spanish','Male'),
('P100048','MRN-900048','susan','wright','1976-06-17','930-13-4569','200 Sessions St','Providence','RI','02906','4015550148','swright@example.com','English','Female'),
('P100049','MRN-900049','ahmed','khalil','1995-11-05','031-24-5670','110 Chad Brown St','Providence','RI','02908','4015550149','akhalil@example.com','Arabic','Male'),
('P100050','MRN-900050','lauren','mccarthy','1981-02-23','132-35-6782','65 Stimson Ave','Providence','RI','02906','4015550150','lmccarthy@example.com','English','Female'),
-- Patients 51-70
('P100051','MRN-900051','joseph','santos','1959-10-10','233-46-7893','18 Parade St','Providence','RI','02909','4015550151','jsantos@example.com','Portuguese','Male'),
('P100052','MRN-900052','karen','lewis','1973-03-16','334-57-8904','140 Congdon St','Providence','RI','02906','4015550152','klewis@example.com','English','Female'),
('P100053','MRN-900053','miguel','cruz','1997-07-28','435-68-9015','315 Chalkstone Ave','Providence','RI','02908','4015550153','mcruz@example.com','Spanish','Male'),
('P100054','MRN-900054','emily','robinson','1985-12-19','536-79-0126','50 Cooke St','Providence','RI','02906','4015550154','erobinson@example.com','English','Female'),
('P100055','MRN-900055','paul','devereaux','1952-01-07','637-80-1237','270 Pleasant Valley Pkwy','Providence','RI','02908','4015550155','pdevereaux@example.com','English','Male'),
('P100056','MRN-900056','carmen','vega','1992-09-24','738-91-2348','83 Daboll St','Providence','RI','02907','4015550156','cvega@example.com','Spanish','Female'),
('P100057','MRN-900057','timothy','brennan','1966-06-13','839-02-3459','45 Humboldt Ave','Providence','RI','02906','4015550157','tbrennan@example.com','English','Male'),
('P100058','MRN-900058','wei','zhang','1989-04-05','940-13-4560','120 John St','Providence','RI','02906','4015550158','wzhang@example.com','Mandarin','Female'),
('P100059','MRN-900059','gregory','white','1978-08-20','041-24-5671','290 Potters Ave','Providence','RI','02907','4015550159','gwhite@example.com','English','Male'),
('P100060','MRN-900060','isabela','oliveira','2002-05-11','142-35-6783','70 Sutton St','Providence','RI','02909','4015550160','ioliveira@example.com','Portuguese','Female'),
('P100061','MRN-900061','donald','murray','1954-02-16','243-46-7894','210 Warrington St','Providence','RI','02907','4015550161','dmurray@example.com','English','Male'),
('P100062','MRN-900062','deepa','patel','1991-11-28','344-57-8905','35 Meeting St','Providence','RI','02906','4015550162','dpatel@example.com','Hindi','Female'),
('P100063','MRN-900063','scott','hennessey','1979-05-04','445-68-9016','180 Oxford St','Providence','RI','02905','4015550163','shennessey@example.com','English','Male'),
('P100064','MRN-900064','amanda','clark','1986-10-22','546-79-0127','24 Verndale Ave','Providence','RI','02905','4015550164','aclark@example.com','English','Female'),
('P100065','MRN-900065','luis','santiago','1970-07-31','647-80-1238','500 Hartford Ave','Providence','RI','02909','4015550165','lsantiago@example.com','Spanish','Male'),
('P100066','MRN-900066','tanya','green','1983-01-18','748-91-2349','90 Doyle Ave','Providence','RI','02906','4015550166','tgreen@example.com','English','Female'),
('P100067','MRN-900067','vincent','rossi','1961-09-07','849-02-3450','325 Federal St','Providence','RI','02903','4015550167','vrossi@example.com','English','Male'),
('P100068','MRN-900068','sunita','rao','1994-06-14','950-13-4561','55 Williams St','Providence','RI','02906','4015550168','srao@example.com','Hindi','Female'),
('P100069','MRN-900069','christopher','dunn','1976-03-26','051-24-5672','168 Cypress St','Providence','RI','02906','4015550169','cdunn@example.com','English','Male'),
('P100070','MRN-900070','maria','costa','1987-12-09','152-35-6784','42 Tell St','Providence','RI','02909','4015550170','macosta@example.com','Portuguese','Female'),
-- Patients 71-85
('P100071','MRN-900071','peter','logan','1963-04-19','253-46-7895','190 Power St','Providence','RI','02906','4015550171','plogan@example.com','English','Male'),
('P100072','MRN-900072','julia','hernandez','1998-08-07','354-57-8906','115 Messer St','Providence','RI','02909','4015550172','jhernandez@example.com','Spanish','Female'),
('P100073','MRN-900073','henry','doyle','1951-10-14','455-68-9017','40 Keene St','Providence','RI','02906','4015550173','hdoyle@example.com','English','Male'),
('P100074','MRN-900074','maya','singh','1993-02-03','556-79-0128','220 Hope St','Providence','RI','02906','4015550174','msingh@example.com','Hindi','Female'),
('P100075','MRN-900075','dennis','mcnamara','1967-06-28','657-80-1239','350 Elmwood Ave','Providence','RI','02907','4015550175','dmcnamara@example.com','English','Male'),
('P100076','MRN-900076','adriana','medeiros','1984-01-12','758-91-2340','80 Pocasset Ave','Providence','RI','02909','4015550176','amedeiros@example.com','Portuguese','Female'),
('P100077','MRN-900077','alan','foster','1972-09-30','859-02-3451','95 Irving Ave','Providence','RI','02906','4015550177','afoster@example.com','English','Male'),
('P100078','MRN-900078','jessica','torres','1996-05-20','960-13-4562','260 Cranston St','Providence','RI','02907','4015550178','jtorres@example.com','Spanish','Female'),
('P100079','MRN-900079','roger','callahan','1955-12-01','061-24-5673','45 Ivy St','Providence','RI','02906','4015550179','rcallahan@example.com','English','Male'),
('P100080','MRN-900080','nadia','ahmed','1990-04-16','162-35-6785','130 Douglas Ave','Providence','RI','02908','4015550180','nahmed@example.com','Arabic','Female'),
('P100081','MRN-900081','mark','fitzgerald','1968-08-08','263-46-7896','78 Prospect St','Providence','RI','02906','4015550181','mfitzgerald@example.com','English','Male'),
('P100082','MRN-900082','carolina','rocha','2001-07-25','364-57-8907','195 Valley St','Providence','RI','02909','4015550182','crocha@example.com','Portuguese','Female'),
('P100083','MRN-900083','charles','griffin','1949-03-17','465-68-9018','55 Creighton St','Providence','RI','02905','4015550183','cgriffin@example.com','English','Male'),
('P100084','MRN-900084','sonia','delgado','1981-11-06','566-79-0129','310 Admiral St','Providence','RI','02908','4015550184','sdelgado@example.com','Spanish','Female'),
('P100085','MRN-900085','andrew','keane','1974-07-22','667-80-1230','140 George St','Providence','RI','02906','4015550185','akeane@example.com','English','Male'),
-- Patients 86-100
('P100086','MRN-900086','thao','le','1988-09-14','768-91-2341','220 Potters Ave','Providence','RI','02907','4015550186','tle@example.com','Vietnamese','Female'),
('P100087','MRN-900087','nicholas','romano','1965-12-30','869-02-3452','60 Fruit Hill Ave','North Providence','RI','02911','4015550187','nromano@example.com','English','Male'),
('P100088','MRN-900088','danielle','power','1979-05-18','970-13-4563','88 Laurel Ave','Providence','RI','02906','4015550188','dpower@example.com','English','Female'),
('P100089','MRN-900089','rafael','soto','1997-01-09','071-24-5674','450 Atwells Ave','Providence','RI','02909','4015550189','rsoto@example.com','Spanish','Male'),
('P100090','MRN-900090','catherine','quinn','1960-06-03','172-35-6786','30 Fones Alley','Providence','RI','02903','4015550190','cquinn@example.com','English','Female'),
('P100091','MRN-900091','derek','washington','1982-10-27','273-46-7897','175 Dudley St','Providence','RI','02905','4015550191','dwashington@example.com','English','Male'),
('P100092','MRN-900092','leila','safar','1993-04-08','374-57-8908','105 Doyle Ave','Providence','RI','02906','4015550192','lsafar@example.com','Arabic','Female'),
('P100093','MRN-900093','bruce','mcdonald','1947-08-15','475-68-9019','210 Gano St','Providence','RI','02906','4015550193','bmcdonald@example.com','English','Male'),
('P100094','MRN-900094','valentina','sousa','1986-02-20','576-79-0120','70 Spruce St','Providence','RI','02903','4015550194','vsousa@example.com','Portuguese','Female'),
('P100095','MRN-900095','harold','carter','1958-11-29','677-80-1231','340 Prairie Ave','Providence','RI','02905','4015550195','hcarter@example.com','English','Male'),
('P100096','MRN-900096','nora','fitzgerald','1995-07-13','778-91-2342','25 Benevolent St','Providence','RI','02906','4015550196','nfitzgerald@example.com','English','Female'),
('P100097','MRN-900097','ivan','petrov','1973-03-06','879-02-3453','190 Public St','Providence','RI','02905','4015550197','ipetrov@example.com','English','Male'),
('P100098','MRN-900098','teresa','baptista','1980-09-22','980-13-4564','285 Manton Ave','Providence','RI','02909','4015550198','tbaptista@example.com','Portuguese','Female'),
('P100099','MRN-900099','ryan','gallagher','2000-12-04','081-24-5675','55 Hope St','Providence','RI','02906','4015550199','rgallagher@example.com','English','Male'),
('P100100','MRN-900100','kimberley','jackson','1970-06-18','182-35-6787','410 Broad St','Providence','RI','02907','4015550200','kjackson@example.com','English','Female');

-- -----------------------------------------------
-- 3b. PAT_ENC - Epic Clarity patient encounters
--     ~7,500 rows generated via GENERATOR (5 yrs)
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

INSERT INTO PAT_ENC (PAT_ENC_CSN_ID,PAT_ID,ENC_TYPE_C,CONTACT_DATE,HOSP_ADMSN_TIME,HOSP_DISCH_TIME,DEPARTMENT_ID,DEPARTMENT_NAME,VISIT_PROV_ID,ACCT_BASECLS_HA,ENC_CLOSED_YN)
WITH dept_info AS (
    SELECT COLUMN1 AS dept_id, COLUMN2 AS dept_name FROM VALUES
        (1001,'Cardiology'),(1002,'Primary Care'),(1003,'Emergency Department'),
        (1004,'Oncology'),(1005,'OB/GYN'),(1006,'Orthopedics'),
        (1007,'Behavioral Health'),(1008,'Nephrology'),(1009,'Neurology'),
        (1010,'Pulmonology'),(1011,'Endocrinology'),(1012,'Gastroenterology'),
        (1013,'General Surgery'),(1014,'Rheumatology'),(1015,'Infectious Disease')
),
enc_raw AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        -- Encounter type: weighted toward outpatient (2) -- ~50% outpatient, ~15% inpatient, ~25% ED, ~10% observation
        CASE
            WHEN MOD(SEQ4() * 7 + 3, 20) < 3  THEN 1   -- Inpatient
            WHEN MOD(SEQ4() * 7 + 3, 20) < 8  THEN 3   -- Emergency
            WHEN MOD(SEQ4() * 7 + 3, 20) < 10 THEN 4   -- Observation
            ELSE 2                                        -- Outpatient
        END AS enc_type,
        -- Spread across 5 years: 2020-01-01 to 2024-11-30
        DATEADD('minute', -(SEQ4() * 35), '2024-11-30 23:59:00'::TIMESTAMP_NTZ) AS admit_ts,
        -- Patient assignment: cycle through 100 patients
        'P' || LPAD((100001 + MOD(SEQ4(), 100))::VARCHAR, 6, '0') AS pat_id,
        -- Provider assignment: cycle through 20 providers
        'PROV-' || LPAD((1 + MOD(SEQ4() * 3, 20))::VARCHAR, 3, '0') AS prov_id,
        -- Department: cycle through 15 departments
        1 + MOD(SEQ4() * 11, 15) AS dept_idx
    FROM TABLE(GENERATOR(ROWCOUNT => 7500))
)
SELECT
    'E' || LPAD(r.rn::VARCHAR, 7, '0')                     AS PAT_ENC_CSN_ID,
    r.pat_id                                                AS PAT_ID,
    r.enc_type                                              AS ENC_TYPE_C,
    r.admit_ts::DATE                                        AS CONTACT_DATE,
    r.admit_ts                                              AS HOSP_ADMSN_TIME,
    CASE
        WHEN r.enc_type = 1 THEN DATEADD('hour', 48 + MOD(r.rn * 7, 120), r.admit_ts)  -- Inpatient: 2-7 days
        WHEN r.enc_type = 3 THEN DATEADD('hour', 2 + MOD(r.rn * 3, 10), r.admit_ts)    -- ED: 2-12 hours
        WHEN r.enc_type = 4 THEN DATEADD('hour', 12 + MOD(r.rn * 5, 36), r.admit_ts)   -- Observation: 12-48 hrs
        ELSE NULL                                                                         -- Outpatient: no discharge
    END                                                     AS HOSP_DISCH_TIME,
    d.dept_id                                               AS DEPARTMENT_ID,
    d.dept_name                                             AS DEPARTMENT_NAME,
    r.prov_id                                               AS VISIT_PROV_ID,
    CASE
        WHEN r.enc_type = 1 THEN ROUND(20000 + MOD(r.rn * 137, 60000), 2)   -- Inpatient: $20K-$80K
        WHEN r.enc_type = 3 THEN ROUND(1000 + MOD(r.rn * 89, 9000), 2)      -- ED: $1K-$10K
        WHEN r.enc_type = 4 THEN ROUND(5000 + MOD(r.rn * 113, 15000), 2)    -- Observation: $5K-$20K
        ELSE ROUND(150 + MOD(r.rn * 53, 650), 2)                             -- Outpatient: $150-$800
    END                                                     AS ACCT_BASECLS_HA,
    'Y'                                                     AS ENC_CLOSED_YN
FROM enc_raw r
JOIN dept_info d ON d.dept_id = (1000 + r.dept_idx);

-- -----------------------------------------------
-- 3c. CLARITY_SER - Epic provider (service employee)
--     20 hand-crafted providers
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
('PROV-008','Dr. Robert Garcia','Nephrology','Nephrology','8901234567','Y'),
('PROV-009','Dr. Helen Tran','Neurology','Neurology','9012345678','Y'),
('PROV-010','Dr. Michael Scott','Pulmonology','Pulmonology','0123456789','Y'),
('PROV-011','Dr. Priya Mehta','Endocrinology','Endocrinology','1122334455','Y'),
('PROV-012','Dr. John Reilly','Gastroenterology','Gastroenterology','2233445566','Y'),
('PROV-013','Dr. Angela Russo','General Surgery','General Surgery','3344556677','Y'),
('PROV-014','Dr. Thomas Lam','Rheumatology','Rheumatology','4455667788','Y'),
('PROV-015','Dr. Maria Souza','Infectious Disease','Infectious Disease','5566778899','Y'),
('PROV-016','Dr. Kevin OBrien','Palliative Care','Palliative Care','6677889900','Y'),
('PROV-017','Dr. Diana Cho','Dermatology','Dermatology','7788990011','Y'),
('PROV-018','Dr. Paul Fernandes','Urology','Urology','8899001122','Y'),
('PROV-019','Dr. Rachel Adams','Radiology','Radiology','9900112233','Y'),
('PROV-020','Dr. Samuel Osei','Pathology','Pathology','0011223344','Y');

-- -----------------------------------------------
-- 3d. ORDER_PROC - Epic lab/procedure orders
--     ~75,000 rows generated via GENERATOR
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

INSERT INTO ORDER_PROC (ORDER_PROC_ID,PAT_ENC_CSN_ID,PAT_ID,PROC_CODE,DESCRIPTION,ORD_VALUE,RESULT_UNIT,REFERENCE_LOW,REFERENCE_HIGH,RESULT_FLAG_C,RESULT_DATE)
WITH labs AS (
    SELECT COLUMN1 AS idx, COLUMN2 AS code, COLUMN3 AS descr,
           COLUMN4 AS unit, COLUMN5 AS ref_lo, COLUMN6 AS ref_hi,
           COLUMN7 AS normal_lo, COLUMN8 AS normal_hi FROM VALUES
        (0, 'CBC',   'Complete Blood Count',           'K/uL',    4.50, 11.00,  5.00,  9.50),
        (1, 'BMP',   'Basic Metabolic Panel',          'mg/dL',   70.00,100.00, 75.00, 95.00),
        (2, 'TROP',  'Troponin I',                     'ng/mL',   0.00,  0.04,  0.00,  0.03),
        (3, 'BNP',   'B-type Natriuretic Peptide',     'pg/mL',   0.00,100.00, 10.00, 80.00),
        (4, 'HBA1C', 'Hemoglobin A1c',                 '%',       4.00,  5.60,  4.20,  5.40),
        (5, 'CREAT', 'Creatinine',                     'mg/dL',   0.70,  1.30,  0.80,  1.10),
        (6, 'GFR',   'Estimated GFR',                  'mL/min', 90.00,120.00, 95.00,115.00),
        (7, 'K',     'Potassium',                      'mEq/L',   3.50,  5.00,  3.70,  4.80),
        (8, 'NA',    'Sodium',                         'mEq/L', 136.00,145.00,137.00,143.00),
        (9, 'WBC',   'White Blood Cell Count',         'K/uL',    4.50, 11.00,  5.00,  9.00),
        (10,'HGB',   'Hemoglobin',                     'g/dL',   12.00, 17.50, 13.00, 16.00),
        (11,'PLT',   'Platelet Count',                 'K/uL',  150.00,400.00,180.00,350.00),
        (12,'ALT',   'Alanine Aminotransferase',       'U/L',     7.00, 56.00, 10.00, 40.00),
        (13,'AST',   'Aspartate Aminotransferase',     'U/L',    10.00, 40.00, 12.00, 35.00),
        (14,'CHOL',  'Total Cholesterol',              'mg/dL',   0.00,200.00,120.00,190.00),
        (15,'LDL',   'LDL Cholesterol',                'mg/dL',   0.00,100.00, 50.00, 90.00),
        (16,'TSH',   'Thyroid Stimulating Hormone',    'mIU/L',   0.40,  4.00,  0.50,  3.50),
        (17,'CRP',   'C-Reactive Protein',             'mg/L',    0.00, 10.00,  0.10,  5.00)
),
ord_raw AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        -- Link to an encounter (cycle through 7500 encounters, ~10 orders each)
        'E' || LPAD((1 + MOD(SEQ4(), 7500))::VARCHAR, 7, '0') AS enc_csn,
        -- Patient from that encounter
        'P' || LPAD((100001 + MOD(MOD(SEQ4(), 7500), 100))::VARCHAR, 6, '0') AS pat_id,
        -- Lab type: cycle through 18 lab types
        MOD(SEQ4() * 7, 18) AS lab_idx,
        -- Abnormal flag: ~20% abnormal (10% high, 10% low)
        CASE
            WHEN MOD(SEQ4() * 13, 10) = 0 THEN 1  -- 10% abnormal high
            WHEN MOD(SEQ4() * 13, 10) = 1 THEN 2  -- 10% abnormal low
            ELSE 0                                   -- 80% normal
        END AS abn_flag,
        -- Result timestamp offset from encounter date
        DATEADD('minute', -(MOD(SEQ4(), 7500) * 35) + MOD(SEQ4() * 17, 480),
                '2024-11-30 23:59:00'::TIMESTAMP_NTZ) AS result_ts
    FROM TABLE(GENERATOR(ROWCOUNT => 75000))
)
SELECT
    'OP' || LPAD(r.rn::VARCHAR, 6, '0')               AS ORDER_PROC_ID,
    r.enc_csn                                          AS PAT_ENC_CSN_ID,
    r.pat_id                                           AS PAT_ID,
    l.code                                             AS PROC_CODE,
    l.descr                                            AS DESCRIPTION,
    CASE
        WHEN r.abn_flag = 1 THEN ROUND(l.ref_hi + (l.ref_hi - l.ref_lo) * (MOD(r.rn * 31, 50) + 10) / 100.0, 2)
        WHEN r.abn_flag = 2 THEN ROUND(l.ref_lo - (l.ref_hi - l.ref_lo) * (MOD(r.rn * 37, 30) + 5) / 100.0, 2)
        ELSE ROUND(l.normal_lo + (l.normal_hi - l.normal_lo) * MOD(r.rn * 41, 100) / 100.0, 2)
    END                                                AS ORD_VALUE,
    l.unit                                             AS RESULT_UNIT,
    l.ref_lo                                           AS REFERENCE_LOW,
    l.ref_hi                                           AS REFERENCE_HIGH,
    r.abn_flag                                         AS RESULT_FLAG_C,
    r.result_ts                                        AS RESULT_DATE
FROM ord_raw r
JOIN labs l ON l.idx = r.lab_idx;

-- -----------------------------------------------
-- 3e. HSP_ACCT_DX_LIST - Diagnosis codes per encounter
--     ~22,500 rows generated via GENERATOR
-- -----------------------------------------------
CREATE OR REPLACE TABLE HSP_ACCT_DX_LIST (
    PAT_ENC_CSN_ID  VARCHAR(20) NOT NULL,
    LINE            NUMBER(3),
    DX_ID           VARCHAR(20),
    ICD10_CODE      VARCHAR(10),
    DX_NAME         VARCHAR(200)
);

INSERT INTO HSP_ACCT_DX_LIST (PAT_ENC_CSN_ID,LINE,DX_ID,ICD10_CODE,DX_NAME)
WITH dx_codes AS (
    SELECT COLUMN1 AS idx, COLUMN2 AS icd10, COLUMN3 AS dx_name FROM VALUES
        (0,  'I21.0',   'ST elevation myocardial infarction'),
        (1,  'I25.10',  'Atherosclerotic heart disease of native coronary artery'),
        (2,  'E11.9',   'Type 2 diabetes mellitus without complications'),
        (3,  'J18.9',   'Pneumonia unspecified organism'),
        (4,  'N18.4',   'Chronic kidney disease stage 4'),
        (5,  'I50.9',   'Heart failure unspecified'),
        (6,  'J44.1',   'Chronic obstructive pulmonary disease with acute exacerbation'),
        (7,  'I10',     'Essential hypertension'),
        (8,  'E78.5',   'Hyperlipidemia unspecified'),
        (9,  'M17.11',  'Primary osteoarthritis right knee'),
        (10, 'F32.1',   'Major depressive disorder single episode moderate'),
        (11, 'R07.9',   'Chest pain unspecified'),
        (12, 'K21.0',   'Gastro-esophageal reflux disease with esophagitis'),
        (13, 'J06.9',   'Acute upper respiratory infection unspecified'),
        (14, 'Z00.00',  'Encounter for general adult medical examination'),
        (15, 'R10.9',   'Unspecified abdominal pain'),
        (16, 'G43.909', 'Migraine unspecified not intractable'),
        (17, 'M54.5',   'Low back pain'),
        (18, 'E03.9',   'Hypothyroidism unspecified'),
        (19, 'N39.0',   'Urinary tract infection site not specified'),
        (20, 'C34.90',  'Malignant neoplasm of unspecified part of bronchus or lung'),
        (21, 'I48.91',  'Unspecified atrial fibrillation'),
        (22, 'E11.22',  'Type 2 diabetes with diabetic chronic kidney disease'),
        (23, 'Z34.00',  'Encounter for supervision of normal first pregnancy'),
        (24, 'K80.20',  'Calculus of gallbladder without cholecystitis'),
        (25, 'D64.9',   'Anemia unspecified'),
        (26, 'B34.9',   'Viral infection unspecified'),
        (27, 'S52.501A','Unspecified fracture of lower end of left radius'),
        (28, 'I20.9',   'Angina pectoris unspecified'),
        (29, 'J45.20',  'Mild intermittent asthma uncomplicated')
),
dx_raw AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        -- Link to encounter (~3 diagnoses per encounter on average)
        'E' || LPAD((1 + MOD(SEQ4(), 7500))::VARCHAR, 7, '0') AS enc_csn,
        -- Line number within encounter (1, 2, or 3)
        MOD(FLOOR((SEQ4()) / 7500), 3) + 1 AS line_num,
        -- Diagnosis index
        MOD(SEQ4() * 13, 30) AS dx_idx
    FROM TABLE(GENERATOR(ROWCOUNT => 22500))
)
SELECT
    r.enc_csn                                          AS PAT_ENC_CSN_ID,
    r.line_num                                         AS LINE,
    'DX' || LPAD(r.rn::VARCHAR, 6, '0')               AS DX_ID,
    d.icd10                                            AS ICD10_CODE,
    d.dx_name                                          AS DX_NAME
FROM dx_raw r
JOIN dx_codes d ON d.idx = r.dx_idx;

-- ============================================================
-- 4. CHECKPOINT: Verify setup
-- ============================================================
SELECT 'PATIENT' AS TBL, COUNT(*) AS ROW_COUNT FROM BUH_HOL.INBOUND.PATIENT
UNION ALL SELECT 'PAT_ENC', COUNT(*) FROM BUH_HOL.INBOUND.PAT_ENC
UNION ALL SELECT 'CLARITY_SER', COUNT(*) FROM BUH_HOL.INBOUND.CLARITY_SER
UNION ALL SELECT 'ORDER_PROC', COUNT(*) FROM BUH_HOL.INBOUND.ORDER_PROC
UNION ALL SELECT 'HSP_ACCT_DX_LIST', COUNT(*) FROM BUH_HOL.INBOUND.HSP_ACCT_DX_LIST
ORDER BY TBL;

/*
  EXPECTED OUTPUT:
  CLARITY_SER           20
  HSP_ACCT_DX_LIST  22,500
  ORDER_PROC        75,000
  PAT_ENC            7,500
  PATIENT              100
*/
