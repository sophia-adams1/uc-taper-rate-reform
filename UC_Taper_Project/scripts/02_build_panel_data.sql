-- =========================================================================
-- PROJECT: UC Taper Rate Reform
-- SCRIPT: 02_build_panel_data.sql
-- AUTHOR: Sophia Adams
-- DATE: 07/08/2026
-- PURPOSE: Join the cleaned geography, UC claimant, ASHE, and APS datasets
-- into one unified panel, master_labour_panel, ready for the DiD/event-study
-- models in 05_did_regression.R.

-- NOTE: run against a PostgreSQL database with la_to_ttwa_lookup, ashe_8_5a_2021,
-- ashe_8_10a_2021, aps_employment_clean, and uc_regional_clean already imported
-- as tables (done manually via DBeaver). Output was exported manually to
-- data-processed/master_labour_panel.csv — this script does not need to be
-- re-run. This script shows the workflow to create master_labour_panel.csv, 
-- which is already saved in the repo, so 03_build_analysis_variables.R is ready
-- for you to run.
-- =========================================================================

-- --- 1. CLEAR ANY TABLES FROM A PREVIOUS RUN ---
DROP TABLE IF EXISTS master_labour_panel;
DROP TABLE IF EXISTS temp_base_lookup;
DROP TABLE IF EXISTS temp_ashe_pay_2021;
DROP TABLE IF EXISTS temp_ashe_hours_2021;
DROP TABLE IF EXISTS temp_annual_aps;

-- ---------------------------------------------------------------------
-- --- 2. GEOGRAPHIC LOOKUP ---
-- Scoped to England & Wales, and recoded onto current (post-April-2023)
-- unitary authority names -- the geography lookup predates the 2023 local
-- government reorganisation, while Stat-Xplore already reports these four
-- areas under their new names, so without this recoding the join below
-- would silently drop all four with no error.
-- ---------------------------------------------------------------------

CREATE TABLE temp_base_lookup AS
WITH la_ttwa_counts AS (
    SELECT
        CASE
            WHEN LAD22NM IN ('Allerdale', 'Carlisle', 'Copeland') THEN 'Cumberland'
            WHEN LAD22NM IN ('Barrow-in-Furness', 'Eden', 'South Lakeland') THEN 'Westmorland and Furness'
            WHEN LAD22NM IN ('Mendip', 'Sedgemoor', 'Somerset West and Taunton', 'South Somerset') THEN 'Somerset'
            WHEN LAD22NM IN ('Craven', 'Hambleton', 'Harrogate', 'Richmondshire', 'Ryedale', 'Scarborough', 'Selby') THEN 'North Yorkshire'
            ELSE LAD22NM
        END AS la_name,
        LAD22CD AS la_code,
        TTWA11CD AS ttwa_code,
        TTWA11NM AS ttwa_name,
        COUNT(*) AS oa_count          -- how many Output Areas of this LA fall in this TTWA
    FROM la_to_ttwa_lookup
    WHERE LAD22CD LIKE 'E%' OR LAD22CD LIKE 'W%'
    GROUP BY 1, 2, 3, 4
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY la_code ORDER BY oa_count DESC) AS rn
    FROM la_ttwa_counts               -- ranks each LA's TTWA matches by overlap size
)
SELECT la_name, la_code, ttwa_code, ttwa_name
FROM ranked
WHERE rn = 1;                          -- keeps only each LA's single dominant TTWA

SELECT la_code, COUNT(*) FROM temp_base_lookup GROUP BY la_code HAVING COUNT(*) > 1;

-- ---------------------------------------------------------------------
-- --- 3. ASHE PAY & HOURS, 2021 ONLY ---
-- Deliberately restricted to the pre-reform year, so the exposure
-- classification built from this in 02_build_analysis_variables.R can't be
-- influenced by any post-reform change in pay or hours -- the classification
-- has to be fixed before the causal comparison can be valid.
-- ---------------------------------------------------------------------

CREATE TABLE temp_ashe_pay_2021 AS
SELECT
    Code AS la_code,
    CASE WHEN Median = 'x' THEN NULL ELSE CAST(Median AS REAL) END AS hourly_pay_median  -- ONS's 'x' marks a small-sample-suppressed cell, cast to a true NULL rather than left as text
FROM ashe_8_5a_2021
WHERE Code LIKE 'E%' OR Code LIKE 'W%';  -- drops the UK/GB/England/region aggregate rows at the top of the raw file

CREATE TABLE temp_ashe_hours_2021 AS
SELECT
    Code AS la_code,
    CASE WHEN Median = 'x' THEN NULL ELSE CAST(Median AS REAL) END AS weekly_hours_median
FROM ashe_8_10a_2021
WHERE Code LIKE 'E%' OR Code LIKE 'W%';

-- ---------------------------------------------------------------------
-- --- 4. APS EMPLOYMENT CONTROLS, YEAR-MATCHED ---
-- Unlike ASHE above, this is deliberately left to vary by year -- it's a
-- genuine annual control, not something the treatment classification is
-- built from, so there's no identification risk in letting it move over time.
-- ---------------------------------------------------------------------

CREATE TABLE temp_annual_aps AS
SELECT la_code, year AS survey_year, economically_active, in_employment, employment_rate_of_active
FROM aps_employment_clean;

-- ---------------------------------------------------------------------
-- --- 5. FINAL MASTER PANEL JOIN ---
-- Combines the monthly UC claimant panel with the geography crosswalk, the
-- year-matched APS controls, and the fixed 2021 ASHE baseline.
-- ---------------------------------------------------------------------

CREATE TABLE master_labour_panel AS
SELECT
    uc.date AS month_date,
    uc.year,
    l.ttwa_code,
    l.ttwa_name,
    l.la_code,
    l.la_name,
    uc.employment_status,
    uc.claimant_count,
    ap.economically_active,
    ap.in_employment,
    ap.employment_rate_of_active,
    pay.hourly_pay_median,
    hrs.weekly_hours_median
FROM uc_regional_clean uc
JOIN temp_base_lookup l ON uc.la_name = l.la_name                                  -- inner join: every UC record should map to a valid area
LEFT JOIN temp_annual_aps ap ON l.la_code = ap.la_code AND uc.year = ap.survey_year -- year-matched, since this control is time-varying
LEFT JOIN temp_ashe_pay_2021 pay ON l.la_code = pay.la_code                        -- no year match -- fixed 2021 baseline, repeated across every month
LEFT JOIN temp_ashe_hours_2021 hrs ON l.la_code = hrs.la_code;

-- ---------------------------------------------------------------------
-- Sanity check before dropping the temp tables -- confirms the crosswalk in
-- Section 2 actually worked. Run manually and check all four areas come
-- back with 24 months of data.
-- ---------------------------------------------------------------------
-- SELECT la_name, COUNT(DISTINCT month_date) FROM master_labour_panel
-- WHERE la_name IN ('Cumberland','Westmorland and Furness','Somerset','North Yorkshire')
-- GROUP BY la_name;

DROP TABLE IF EXISTS temp_base_lookup;
DROP TABLE IF EXISTS temp_ashe_pay_2021;
DROP TABLE IF EXISTS temp_ashe_hours_2021;
DROP TABLE IF EXISTS temp_annual_aps;

-- ------------------------------------------------
SELECT * FROM master_labour_panel;


SELECT la_code, month_date, employment_status, COUNT(*) 
FROM master_labour_panel 
GROUP BY la_code, month_date, employment_status 
HAVING COUNT(*) > 1;

