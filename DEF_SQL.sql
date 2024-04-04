-- Join tables to obtain a main 'forestation' view
DROP VIEW IF EXISTS forestation;
CREATE VIEW forestation AS
    SELECT forest.country_code, 
    forest.country_name,
    forest.year, 
    ROUND(forest.forest_area_sqkm, 2) AS forest_area_sqkm,
    ROUND(land.total_area_sq_mi * 2.59, 2) AS total_area_sqkm,
    ROUND(forest.forest_area_sqkm/(land.total_area_sq_mi * 2.59) * 100, 2) AS pct_forest, 
    reg.region, 
    reg.income_group
FROM forest_area AS forest
JOIN land_area AS land
ON forest.country_code = land.country_code
    AND forest.year = land.year
JOIN regions AS reg
ON forest.country_code = reg.country_code
WHERE forest.year IN (1990, 2016);

-- Obtain information for the world in 1990 and 2016. Save view to use for other queries
CREATE VIEW world_data AS
SELECT year, forest_area_sqkm, total_area_sqkm, pct_forest
FROM forestation
WHERE country_name = 'World';

-- Compute difference in metrics from 1990 to 2016  
SELECT 
    (SELECT forest_area_sqkm FROM world_data WHERE year = 2016) - (
        SELECT forest_area_sqkm FROM world_data WHERE year = 1990) AS forest_difference,
    ((SELECT forest_area_sqkm FROM world_data WHERE year = 2016) - (
        SELECT forest_area_sqkm FROM world_data WHERE year = 1990))/
        (SELECT forest_area_sqkm FROM world_data WHERE year = 1990) *100 AS pct_change
FROM world_data;

-- Alternative computation of metrics difference using a self join
SELECT past.country_name, 
    (present.forest_area_sqkm - past.forest_area_sqkm) AS forest_difference,
    (present.forest_area_sqkm - past.forest_area_sqkm)/past.forest_area_sqkm *100 AS pct_change, 
FROM forestation AS past
JOIN forestation AS present
ON past.country_name = present.country_name
WHERE past.year = 1990 
    AND present.year = 2016
    AND country_name = 'World';

-- Find the country with a total area similar to the world forest area lost between 1990-2016
SELECT country_name, 
    total_area_sqkm 
FROM forestation 
    WHERE year = 2016 
    AND total_area_sqkm <= 
        (SELECT 
            (SELECT forest_area_sqkm FROM world_data WHERE year = 1990) - 
            (SELECT forest_area_sqkm FROM world_data WHERE year = 2016) AS forest_difference
        FROM world_data)
ORDER BY total_area_sqkm DESC;

-- Create regional view to answer which world regions saw a forest percent decrease
-- Note forest_area_sqkm and total_area_sqkm have NULL values if you query them in descending order so need to remove these.
CREATE OR REPLACE VIEW regional_change AS
WITH forest_percentage_1990 AS (
    SELECT region,
        SUM(forest_area_sqkm)/SUM(total_area_sqkm)*100 AS pct_forest_1990
    FROM forestation
    WHERE year = 1990 
        AND forest_area_sqkm IS NOT NULL 
        AND total_area_sqkm IS NOT NULL
    GROUP BY region),
forest_percentage_2016 AS (
    SELECT region,
        SUM(forest_area_sqkm)/SUM(total_area_sqkm)*100 AS pct_forest_2016
    FROM forestation
    WHERE year = 2016 
        AND forest_area_sqkm IS NOT NULL 
        AND total_area_sqkm IS NOT NULL
    GROUP BY region)
SELECT past.region, 
    past.pct_forest_1990,
    present.pct_forest_2016
FROM forest_percentage_1990 AS past
JOIN forest_percentage_2016 AS present
ON past.region = present.region;

-- Cases where forest area decreased from 1990 to 2016
SELECT *
FROM regional_change
WHERE pct_forest_2016 < pct_forest_1990;

-- Create country-level view to look at country details
-- Note that income_group was selected for 1990 and 2016. This was because it would not be impossible for some countries to have changed their income group bracket from 1990 and 2016. However, another query not included in these final ones showed this column did not differ between years. Thus, only the 1990 column for region is included afer the CTEs.
CREATE OR REPLACE VIEW country_change AS
WITH forest_1990 AS (
    SELECT country_name,
        forest_area_sqkm AS forest_area_1990,
        total_area_sqkm AS total_area_1990,
        pct_forest AS pct_forest_1990,
        region, 
        income_group AS income_1990
    FROM forestation
    WHERE year = 1990),
forest_2016 AS (
    SELECT country_name,
        forest_area_sqkm AS forest_area_2016,
        total_area_sqkm AS total_area_2016,
        pct_forest AS pct_forest_2016,
        region, income_group AS income_2016
    FROM forestation
    WHERE year = 2016)
SELECT past.country_name,
    (present.forest_area_2016 - past.forest_area_1990) AS forest_area_change,
    (present.forest_area_2016 - past.forest_area_1990)/
        past.forest_area_1990 * 100 AS forest_pct_change,   
    past.income_1990,
    past.region
FROM forest_1990 AS past
JOIN forest_2016 AS present
ON past.country_name = present.country_name
WHERE (present.forest_area_2016 - past.forest_area_1990) IS NOT NULL
    AND past.country_name <> 'World';

-- Countries with the greatest increase in forest area in sqkm
SELECT country_name, forest_area_change
FROM country_change
ORDER BY 2 DESC;

-- Countries with the greatest forest area percentage increase
SELECT country_name, forest_pct_change
FROM country_change
ORDER BY 2 DESC;

-- Top 5 countries with the greatest loss of absolute forest area
SELECT country_name, region, forest_area_change
FROM country_change
ORDER BY 3
LIMIT 5;

-- Top 5 countries with greatest decrease in forest area percentage
SELECT country_name, region, forest_pct_change
FROM country_change
ORDER BY 3
LIMIT 5;

-- Create quartiles view to divide countries into quartiles based on the percent of land designated as forest in 2016
CREATE OR REPLACE VIEW quartiles AS
SELECT country_name, region, 
    pct_forest_2016,
    CASE WHEN pct_forest_2016 BETWEEN 0 AND 24.99 THEN 'Under 25%'
        WHEN pct_forest_2016 BETWEEN 25 AND 50 THEN 'Between 25% to 50%'
        WHEN pct_forest_2016 > 50 AND pct_forest_2016 < 75 THEN 'Between 50% to 75%'
        ELSE 'Over 75%' END AS forest_quartile
FROM country_change
WHERE pct_forest_2016 IS NOT NULL 
    AND country_name NOT LIKE 'World'
ORDER BY 3 DESC;

-- Group by quartiles and count the number of countries in each
SELECT forest_quartile, COUNT(*) AS number_countries
FROM quartiles
GROUP BY 1
ORDER BY 2 DESC;

-- Because Sub-Saharan Africa was a particularly deforested region and thus it was recommended ForestQuery's efforts looked into it, this region was queried into more detail. Specifically, given 4 of 5 countries with the greatest decrease in their forest percentage were in this region and were of middle low and low income brackets (which could impact the funding for forestation interventions), we looked at whether other countries of the same income had seen successful reforestation efforts (or just a forest area change greater than 0) that ForestQuery could draw insight from.
SELECT country_name, 
    forest_pct_change, 
    forest_area_change
FROM country_change
WHERE forest_area_change IS NOT NULL 
    AND country_name NOT LIKE 'World'
    AND region = 'Sub-Saharan Africa' 
    AND (income_2016 = 'Low income' OR income_2016 = 'Lower middle income'
    AND forest_area_change > 0
ORDER BY 2 DESC;