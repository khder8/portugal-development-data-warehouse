-- =============================================================================
-- AID 2026/2027 - Project, Group 16
-- Task 1: exploratory queries on the staging database aid_staging
-- The results of these queries were used to write the three data dictionaries.
-- =============================================================================

USE aid_staging;

-- -----------------------------------------------------------------------------
-- 1. Size of the three staging tables and year span
-- -----------------------------------------------------------------------------
SELECT 'stg_maddison' AS source_table, COUNT(*) AS n_rows, MIN(year) AS min_year, MAX(year) AS max_year FROM stg_maddison
UNION ALL
SELECT 'stg_wdi', COUNT(*), MIN(year), MAX(year) FROM stg_wdi
UNION ALL
SELECT 'stg_events', COUNT(*), MIN(year), MAX(year) FROM stg_events;

-- -----------------------------------------------------------------------------
-- 2. Countries in each source and number of rows per country
-- -----------------------------------------------------------------------------
SELECT country_iso3, country_name, COUNT(*) AS n_rows
FROM stg_maddison
GROUP BY country_iso3, country_name
ORDER BY country_iso3;

SELECT country_iso3, country_name, COUNT(*) AS n_rows
FROM stg_wdi
GROUP BY country_iso3, country_name
ORDER BY country_iso3;

SELECT country_iso3, country_name, COUNT(*) AS n_rows
FROM stg_events
GROUP BY country_iso3, country_name
ORDER BY country_iso3;

-- share of the events for each country (Portugal has about one third)
SELECT country_iso3, country_name,
       COUNT(*) AS n_events,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM stg_events), 1) AS pct_of_events
FROM stg_events
GROUP BY country_iso3, country_name
ORDER BY n_events DESC;

-- -----------------------------------------------------------------------------
-- 3. Indicators: rows, countries, period and range of values
-- -----------------------------------------------------------------------------
SELECT indicator_code, indicator_name, COUNT(*) AS n_rows,
       COUNT(DISTINCT country_iso3) AS n_countries,
       MIN(year) AS first_year, MAX(year) AS last_year,
       MIN(value) AS min_value, MAX(value) AS max_value
FROM stg_maddison
GROUP BY indicator_code, indicator_name;

SELECT indicator_code, indicator_name, COUNT(*) AS n_rows,
       COUNT(DISTINCT country_iso3) AS n_countries,
       MIN(year) AS first_year, MAX(year) AS last_year,
       MIN(value) AS min_value, MAX(value) AS max_value
FROM stg_wdi
GROUP BY indicator_code, indicator_name
ORDER BY indicator_code;

-- -----------------------------------------------------------------------------
-- 4. Temporal coverage and gaps in Maddison
-- -----------------------------------------------------------------------------
-- number of missing years inside the period of each series
SELECT country_iso3, indicator_code,
       MIN(year) AS first_year, MAX(year) AS last_year, COUNT(*) AS n_years,
       MAX(year) - MIN(year) + 1 - COUNT(*) AS missing_years
FROM stg_maddison
GROUP BY country_iso3, indicator_code
ORDER BY country_iso3, indicator_code;

-- only the series that have gaps
SELECT country_iso3, indicator_code,
       MIN(year) AS first_year, MAX(year) AS last_year, COUNT(*) AS n_years,
       MAX(year) - MIN(year) + 1 - COUNT(*) AS missing_years
FROM stg_maddison
GROUP BY country_iso3, indicator_code
HAVING missing_years > 0
ORDER BY country_iso3, indicator_code;

-- exact position of each gap (LEAD gives the next available year)
SELECT country_iso3, indicator_code,
       year + 1             AS gap_from,
       next_year - 1        AS gap_to,
       next_year - year - 1 AS missing_years
FROM (
    SELECT country_iso3, indicator_code, year,
           LEAD(year) OVER (PARTITION BY country_iso3, indicator_code
                            ORDER BY year) AS next_year
    FROM stg_maddison
) AS t
WHERE next_year - year > 1
ORDER BY country_iso3, indicator_code, gap_from;

-- years where not all three Maddison indicators exist (Romania 1901-1919)
SELECT country_iso3, year,
       GROUP_CONCAT(indicator_code) AS available_indicators
FROM stg_maddison
GROUP BY country_iso3, year
HAVING COUNT(*) < 3
ORDER BY country_iso3, year;

-- -----------------------------------------------------------------------------
-- 5. Temporal coverage in WDI by country (first and last year of the main series)
-- -----------------------------------------------------------------------------
SELECT country_iso3,
       COUNT(*) AS n_rows,
       MIN(CASE WHEN indicator_code = 'NY.GDP.MKTP.KD.ZG' THEN year END) AS gdp_growth_from,
       MIN(CASE WHEN indicator_code = 'NY.GNP.PCAP.CD'    THEN year END) AS gni_from,
       MIN(CASE WHEN indicator_code = 'NV.AGR.TOTL.ZS'    THEN year END) AS sector_shares_from,
       MIN(CASE WHEN indicator_code = 'SL.AGR.EMPL.ZS'    THEN year END) AS employment_from
FROM stg_wdi
GROUP BY country_iso3
ORDER BY country_iso3;

-- -----------------------------------------------------------------------------
-- 6. Country coverage between sources (EUU exists in WDI but not in Maddison)
-- -----------------------------------------------------------------------------
SELECT DISTINCT country_iso3, country_name
FROM stg_wdi
WHERE country_iso3 NOT IN (SELECT country_iso3 FROM stg_maddison);

-- same ISO3 code with a different name in two sources (expected: no rows)
SELECT w.country_iso3, w.country_name AS wdi_name, m.country_name AS maddison_name
FROM (SELECT DISTINCT country_iso3, country_name FROM stg_wdi) w
JOIN (SELECT DISTINCT country_iso3, country_name FROM stg_maddison) m
  ON m.country_iso3 = w.country_iso3
WHERE m.country_name <> w.country_name;

-- -----------------------------------------------------------------------------
-- 7. Quality checks: missing values, duplicates and impossible values
-- -----------------------------------------------------------------------------
-- missing or empty values
SELECT 'stg_maddison' AS source_table, COUNT(*) AS n_rows, SUM(value IS NULL) AS missing_values FROM stg_maddison
UNION ALL
SELECT 'stg_wdi', COUNT(*), SUM(value IS NULL) FROM stg_wdi
UNION ALL
SELECT 'stg_events', COUNT(*), SUM(event = '' OR category = '' OR economic_impact = '') FROM stg_events;

-- duplicated keys (expected: no rows; the primary key would also reject them)
SELECT country_iso3, indicator_code, year, COUNT(*) AS n
FROM stg_maddison
GROUP BY country_iso3, indicator_code, year
HAVING COUNT(*) > 1;

SELECT country_iso3, indicator_code, year, COUNT(*) AS n
FROM stg_wdi
GROUP BY country_iso3, indicator_code, year
HAVING COUNT(*) > 1;

-- duplicated events (same country, year and text; expected: no rows)
SELECT country_iso3, year, event, COUNT(*) AS n
FROM stg_events
GROUP BY country_iso3, year, event
HAVING COUNT(*) > 1;

-- negative values or percentages above 100 in WDI
-- (negative GDP growth and trade above 100% of GDP are real values, not errors)
SELECT indicator_code, COUNT(*) AS n_rows, MIN(value) AS min_value, MAX(value) AS max_value
FROM stg_wdi
WHERE value < 0 OR (indicator_code LIKE '%.ZS' AND value > 100)
GROUP BY indicator_code;

-- -----------------------------------------------------------------------------
-- 8. Maximum text lengths, used to choose the VARCHAR sizes
-- -----------------------------------------------------------------------------
SELECT 'stg_maddison' AS source_table,
       MAX(CHAR_LENGTH(country_name))   AS max_country_name,
       MAX(CHAR_LENGTH(indicator_code)) AS max_indicator_code,
       MAX(CHAR_LENGTH(indicator_name)) AS max_indicator_name
FROM stg_maddison
UNION ALL
SELECT 'stg_wdi',
       MAX(CHAR_LENGTH(country_name)), MAX(CHAR_LENGTH(indicator_code)), MAX(CHAR_LENGTH(indicator_name))
FROM stg_wdi;

SELECT MAX(CHAR_LENGTH(country_name))    AS max_country_name,
       MAX(CHAR_LENGTH(event))           AS max_event,
       MAX(CHAR_LENGTH(category))        AS max_category,
       MAX(CHAR_LENGTH(economic_impact)) AS max_economic_impact
FROM stg_events;

-- -----------------------------------------------------------------------------
-- 9. Events: categories, decades and impact labels
-- -----------------------------------------------------------------------------
SELECT category, COUNT(*) AS n_events
FROM stg_events
GROUP BY category
ORDER BY n_events DESC;

SELECT FLOOR(year / 10) * 10 AS decade, COUNT(*) AS n_events
FROM stg_events
GROUP BY decade
ORDER BY decade;

SELECT COUNT(DISTINCT economic_impact) AS n_distinct_labels
FROM stg_events;

SELECT economic_impact, COUNT(*) AS n_events
FROM stg_events
GROUP BY economic_impact
ORDER BY n_events DESC;

-- country-years with more than one event (reason for the bridge table in Task 3)
SELECT country_iso3, year, COUNT(*) AS n_events
FROM stg_events
GROUP BY country_iso3, year
HAVING COUNT(*) > 1
ORDER BY n_events DESC, country_iso3, year;

-- -----------------------------------------------------------------------------
-- 10. WDI indicator list and the Industry / Manufacturing overlap
-- -----------------------------------------------------------------------------
SELECT DISTINCT indicator_code, indicator_name
FROM stg_wdi
ORDER BY indicator_code;

SELECT DISTINCT indicator_code, indicator_name
FROM stg_wdi
WHERE indicator_code LIKE '%MANF%';

-- manufacturing is part of industry: for Portugal it is always smaller
SELECT year, indicator_code, indicator_name, ROUND(value, 1) AS value
FROM stg_wdi
WHERE country_iso3 = 'PRT'
  AND indicator_code IN ('NV.IND.TOTL.ZS', 'NV.IND.MANF.ZS')
ORDER BY year;
