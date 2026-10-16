-- Loads the case-study mock rows into RAW.SALESFORCE so the whole project can run end to end
-- in a Snowflake trial account. Column values are exactly as given in the PDF (text amounts with
-- commas, '2026- 06-10' dates, TRUE/FALSE strings).
-- Added because a real Fivetran sync has them but the PDF omitted them:
--   _fivetran_synced, _fivetran_deleted on every table; is_deleted on account/contact/activity;
--   owner_id on account (left NULL: not in the extract).
-- USER and OPPORTUNITY_HISTORY are created EMPTY: the extract does not include them. The project
-- still runs: owners show as 'Unknown owner' (and a warn test says so), and history falls back to
-- each deal's current state since creation.

use role sysadmin;
create database if not exists raw;
create schema if not exists raw.salesforce;
use schema raw.salesforce;

create or replace table opportunity (
    opp_id varchar, account_id varchar, owner_id varchar, stage_name varchar, amount varchar,
    close_date varchar, type varchar, is_deleted varchar, created_date varchar,
    _fivetran_synced timestamp_ntz, _fivetran_deleted boolean
);
insert into opportunity values
    ('006A','001A','005A','Closed Won', '250,000','2025-03-31','New Business','FALSE','2024-10-01 09:00:00','2026-10-16 06:00:00',false),
    ('006B','001B','005A','Negotiation','85,000', '2026-07-31','New Business','FALSE','2026-02-14 11:30:00','2026-10-16 06:00:00',false),
    ('006C','001C','005B','Proposal',   '320,000','2026-08-15','Renewal',     'FALSE','2026-03-01 10:00:00','2026-10-16 06:00:00',false),
    ('006D','001D','005B','Prospecting',NULL, '2026-09-30','New Business','FALSE','2026-06-15 14:20:00','2026-10-16 06:00:00',false),
    ('006E','001E','005C','Discovery',  '95,000', '2026-08-31','New Business','FALSE','2026-04-10 08:45:00','2026-10-16 06:00:00',false),
    ('006F','001A','005A','Closed Lost','75,000', '2025-12-31','Expansion',   'FALSE','2025-09-01 13:00:00','2026-10-16 06:00:00',false),
    ('006G','001C','005C','Discovery',  NULL, '2026-10-31','New Business','TRUE', '2026-01-05 09:15:00','2026-10-16 06:00:00',false),
    ('006H','001B','005B','Closed Won', '85,000', '2026-05-15','Renewal',     'FALSE','2025-11-01 10:00:00','2026-10-16 06:00:00',false);

create or replace table account (
    account_id varchar, account_name varchar, industry varchar, segment varchar, arr varchar,
    state varchar, created_date varchar, owner_id varchar, is_deleted varchar,
    _fivetran_synced timestamp_ntz, _fivetran_deleted boolean
);
insert into account values
    ('001A','City of Austin',       'Government','Enterprise','250,000','TX','2023-01-15 00:00:00',NULL,'FALSE','2026-10-16 06:00:00',false),
    ('001B','Austin ISD',           'Education', 'Mid-Market','85,000', 'TX','2023-06-01 00:00:00',NULL,'FALSE','2026-10-16 06:00:00',false),
    ('001C','Harris County',        'Government','Enterprise','320,000','TX','2022-09-10 00:00:00',NULL,'FALSE','2026-10-16 06:00:00',false),
    ('001D','Springfield Utilities','Utilities', 'SMB',       '18,000', 'IL','2024-02-20 00:00:00',NULL,'FALSE','2026-10-16 06:00:00',false),
    ('001E','Denver Public Schools','Education', 'Mid-Market','95,000', 'CO','2024-05-05 00:00:00',NULL,'FALSE','2026-10-16 06:00:00',false);

create or replace table contact (
    contact_id varchar, account_id varchar, full_name varchar, title varchar, email varchar,
    created_date varchar, is_deleted varchar, _fivetran_synced timestamp_ntz, _fivetran_deleted boolean
);
insert into contact values
    ('003A','001A','John Hernandez','Budget Director',      'j.hernandez@austin.gov',      '2024-10-01 09:00:00','FALSE','2026-10-16 06:00:00',false),
    ('003B','001B','Sarah Chen',    'IT Director',          's.chen@austinisd.org',        '2026-02-14 11:30:00','FALSE','2026-10-16 06:00:00',false),
    ('003C','001C','Mike Torres',   'Procurement Manager',  'm.torres@harriscounty.gov',   '2026-03-01 10:00:00','FALSE','2026-10-16 06:00:00',false),
    ('003D','001D','Lisa Park',     'Chief Information Off','l.park@springfieldutils.com', '2026-06-15 14:20:00','FALSE','2026-10-16 06:00:00',false),
    ('003E','001E','David Kim',     'Finance Officer',      'd.kim@denverps.org',          '2026-04-10 08:45:00','FALSE','2026-10-16 06:00:00',false);

create or replace table activity (
    activity_id varchar, opp_id varchar, contact_id varchar, type varchar, subject varchar,
    activity_date varchar, created_date varchar, is_deleted varchar,
    _fivetran_synced timestamp_ntz, _fivetran_deleted boolean
);
insert into activity values
    ('00TA','006B','003B','Call',   'Intro call — pricing discussion',  '2026- 06-10','2026-06-10 14:00:00','FALSE','2026-10-16 06:00:00',false),
    ('00TB','006B','003B','Email',  'Sent proposal document',           '2026- 06-12','2026-06-12 09:30:00','FALSE','2026-10-16 06:00:00',false),
    ('00TC','006C','003C','Meeting','Executive sponsor QBR',            '2026- 06-20','2026-06-20 10:00:00','FALSE','2026-10-16 06:00:00',false),
    ('00TD','006E','003E','Call',   'Discovery call #1',                '2026- 05-01','2026-05-01 11:00:00','FALSE','2026-10-16 06:00:00',false),
    ('00TE','006E','003E','Email',  'Follow-up: budget timeline',       '2026- 05-15','2026-05-15 08:00:00','FALSE','2026-10-16 06:00:00',false),
    ('00TF','006D','003D','Call',   'Cold outreach — initial contact',  '2026- 06-16','2026-06-16 15:45:00','FALSE','2026-10-16 06:00:00',false);

-- Not in the extract: created empty with the real Fivetran column names.
create or replace table "USER" (
    id varchar, name varchar, email varchar, manager_id varchar, user_role_id varchar,
    is_active boolean, _fivetran_synced timestamp_ntz, _fivetran_deleted boolean
);

create or replace table opportunity_history (
    id varchar, opportunity_id varchar, created_date varchar, stage_name varchar, amount varchar,
    close_date varchar, probability number, forecast_category varchar, is_deleted varchar,
    _fivetran_synced timestamp_ntz, _fivetran_deleted boolean
);
