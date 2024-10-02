
-- VIEW Spojení tabulek payroll

CREATE OR REPLACE VIEW joining_payroll_tables AS 
SELECT payroll_year
       ,czechia_payroll_value_type.name 	   AS value_type
       ,czechia_payroll_calculation.name 	   AS calculation		
       ,value
       ,czechia_payroll_unit.name 		 	   AS unit
       ,CASE 
       		WHEN czechia_payroll_industry_branch.name IS NULL
       		THEN 'Ostatní'
       		ELSE czechia_payroll_industry_branch.name
        END 								   AS industry_branch
FROM czechia_payroll
JOIN czechia_payroll_value_type
	ON czechia_payroll.value_type_code = czechia_payroll_value_type.code
JOIN czechia_payroll_unit 
	ON czechia_payroll.unit_code = czechia_payroll_unit.code
JOIN czechia_payroll_calculation
	ON czechia_payroll.calculation_code = czechia_payroll_calculation.code 
LEFT JOIN czechia_payroll_industry_branch
		 ON czechia_payroll.industry_branch_code = czechia_payroll_industry_branch.code
WHERE czechia_payroll_unit.name = 'Kč' 
	 AND czechia_payroll_calculation.name = 'přepočtený'
ORDER BY payroll_year
;


-- VIEW Spojení tabulek price -- 

CREATE OR REPLACE VIEW joining_price_tables AS
SELECT TO_CHAR (date_from, 'YYYY') AS price_year,
	   czechia_price_category.name AS price_name,
 	   ROUND(AVG(value), 1)  	   AS price_value,	   
	   price_value 				   AS price_value_unit,
	   price_unit,
	   czechia_region.name 		   AS region
FROM czechia_price
JOIN czechia_price_category
		 ON category_code = czechia_price_category.code
LEFT JOIN czechia_region
		 ON region_code = czechia_region.code
GROUP BY price_year
		 ,price_name
ORDER BY price_name, price_year
;


-- Výsledná tabulka ve spojení VIEWs: spojeni tabulek payroll a price --
task

CREATE OR REPLACE TABLE t_petr_luka_project_SQL_primary_final AS
WITH price_group AS (
SELECT price_year
	   ,price_name
	   ,price_value
	   ,price_value_unit
	   ,price_unit
	   ,CASE 
	   		WHEN price_year = 2006 OR price_value IS NULL
	   		THEN 0
	   		ELSE (price_value) 
	   			- (LAG(price_value, 1) 
	   			      OVER (
	   			      	  ORDER BY price_name 
	   						   		 ,price_year))
	    END 								    AS price_value_diff
FROM joining_price_tables
) ,payroll_group AS (
SELECT payroll_year
	   ,ROUND(AVG(value), 1) 			        AS payroll_value
	   ,unit							        AS payroll_unit
	   ,industry_branch
	   ,(ROUND(AVG(value), 1) 
	    - (LAG(ROUND(AVG(value),0),1) 
		 	   OVER (
		 		   ORDER BY industry_branch
		   		  			,payroll_year )))   AS payroll_value_diff
	FROM joining_payroll_tables
	GROUP BY  industry_branch, payroll_year
	)
SELECT payroll_year 					  	    AS common_year
	   ,industry_branch 				        AS payroll_industry_branch
	   ,price_name
	   ,price_value
	   ,price_value_unit
	   ,price_unit
	   ,payroll_value
	   ,payroll_unit
	   ,ROUND((payroll_value / price_value), 1) AS name_count
	   ,payroll_value_diff
	   ,CASE 
		    WHEN payroll_value_diff < 0
		    THEN ROUND(((payroll_value_diff / payroll_value) * 100),1)
		    WHEN payroll_value_diff >= 0
		    THEN ROUND(((payroll_value_diff / payroll_value) * 100),1)
		    ELSE 0
		END 									AS payroll_value_percent
	   ,price_value_diff
	   ,CASE 
		    WHEN payroll_year = 2006 OR price_unit IS NULL
		    THEN 0
		    ELSE ROUND(((price_value_diff / price_value) * 100),1)
		END 									AS price_value_percent
FROM payroll_group
LEFT JOIN price_group
	 ON payroll_year = price_year
WHERE payroll_year > 2000
GROUP BY payroll_year
         ,industry_branch
         ,price_name
;

-- výzkumné otázky --

-- 1. Rostou v průběhu let mzdy ve všech odvětvích, nebo v některých klesají? --
-- Odpověď: Z dlouhodobého hlediska rostou mzdy ve všech odvětí, ale z krátkodobého hlediska v některých odvětvích v průběhu let mzdy klesají. Nejčastěji v oboru Těžby a dobývání --

SELECT payroll_industry_branch
	   ,COUNT(common_year) 				AS payroll_count
FROM(
	SELECT payroll_industry_branch
	   	   ,common_year
	   	   ,payroll_value_percent
	FROM t_petr_luka_project_SQL_primary_final
GROUP BY payroll_industry_branch
		 ,common_year) 					AS tab_select
WHERE payroll_value_percent < 0
GROUP BY payroll_industry_branch
ORDER BY payroll_count DESC
		 ,payroll_industry_branch ASC
;

-- 2. Kolik je možné si koupit litrů mléka a kilogramů chleba za první a poslední srovnatelné období v dostupných datech cen a mezd? --
-- Odpověď: viz tabulka níže, kde lze vidět, že v roce 2006 lze koupit 1 309,5 Kg Chleba a nebo 1 464,1 litrů mléka za průměrnou mzdu v tomto roce. --
-- V roce 2018 lze zakoupit 1 365,2 Kg chleba nebo 1668,6 litrů mléka. --

SELECT common_year 
	   ,price_name 
	   ,ROUND((AVG(payroll_value) / price_value), 1) AS count_value
	   ,price_unit
FROM t_petr_luka_project_SQL_primary_final
WHERE price_name 
	 IN ('Mléko polotučné pasterované', 'Chléb konzumní kmínový') 
	 AND common_year 
	 IN (2006, 2018)
GROUP BY common_year 
		 ,price_name
;

-- 3. Která kategorie potravin zdražuje nejpomaleji (je u ní nejnižší percentuální meziroční nárůst)? --
-- Odpověď: Nejpomaleji zdražují Rajská jablka červená kulatá. V průměru meziročně zlevnila o 3,8%.
SELECT price_name
	   ,ROUND(AVG(price_value_percent), 1) AS percent_avg
FROM t_petr_luka_project_SQL_primary_final
WHERE price_name IS NOT NULL 
	 AND common_year > 2006
GROUP BY price_name 
ORDER BY percent_avg
LIMIT 1
;


-- 4. Existuje rok, ve kterém byl meziroční nárůst cen potravin výrazně vyšší než růst mezd (větší než 10 %)? --
-- Odpověď: NE, nejvyšší meziroční nárust cen potravin oproti nárustu mezd byl v roce 2013 o 5,4 % --
SELECT common_year
	   ,ROUND(AVG(price_value_percent), 1) 
	    - ROUND(AVG(payroll_value_percent), 1) AS difference_value_percent
FROM t_petr_luka_project_SQL_primary_final
WHERE common_year > 2006 
	 AND common_year < 2019
GROUP BY common_year
ORDER BY difference_value_percent DESC
LIMIT 1
;

-- Má výška HDP vliv na změny ve mzdách a cenách potravin? Neboli, pokud HDP vzroste výrazněji v jednom roce, projeví se to na cenách potravin či mzdách ve stejném nebo násdujícím roce výraznějším růstem?--
-- Odpověď: Není tomu tak vždy. Chybí data z roku 2019 pro tabulku cen potravin. Kdybychom měli tato data a ukázalo by se, že mezi rokem 2018 - 2019 byl nárust ceny vyšší než 4 % tak dle vypočtených dat vychází:
--          Pokud HDP vzrostlo o více jak 4 %, tak nárust cen potravin i platů narostl ve stejném a zároveň v následujícím roce o více jak 4 % přesně ve dvou ze tří případů.
--          S daty, které máme, můžeme říci, že pokud HDP vzrostlo o více jak 4 %, tak o více jak 4 % vzrostly platy i ceny potravin ve dvou ze tří případů a v následujícím roce platy ve dvou ze tří případů a ceny potravin v jednom ze tří případů.
WITH gdp_join AS (
SELECT economies.`year` 
	   ,gdp
	   ,ROUND((((gdp - (
	   		 LAG(gdp, 1) 
		 		OVER (
		 			ORDER BY `year`)))/gdp)*100), 1) AS gdp_value_percent		
FROM economies
WHERE country = 'Czech Republic' 
)
,price_and_payroll AS (
SELECT common_year
	   ,ROUND(AVG(payroll_value_percent), 1)         AS avg_payroll_perc
	   ,ROUND(AVG(price_value_percent), 1)           AS avg_price_perc
	   ,LEAD(ROUND(AVG(payroll_value_percent), 1))
		   OVER (
		   	   ORDER BY common_year) 			 	 AS lead_payroll
	   ,LEAD(ROUND(AVG(price_value_percent), 1))
		   OVER (
		   	   ORDER BY common_year) 				 AS lead_price
FROM t_petr_luka_project_SQL_primary_final
GROUP BY common_year
ORDER BY common_year
)
SELECT common_year
	   ,CASE 
		    WHEN (gdp_value_percent > 4 
		    	AND avg_payroll_perc > 4
		    	AND avg_price_perc > 4)
	   		THEN 'Payroll and Price are Higer'
	   		WHEN gdp_value_percent > 4 
	   			AND avg_payroll_perc > 4
	   		THEN 'Payroll is Higher'
	   		WHEN gdp_value_percent > 4 
	   			AND avg_price_perc > 4
	   		THEN 'Price is Higher'
	   		WHEN gdp_value_percent > 4
	   			AND (avg_price_perc
	   			OR avg_price_perc) < 4
	   		THEN 'Has NO effect'
	   		ELSE '-'
	   END                                           AS same_year_differences
	   ,CASE 
		    WHEN (gdp_value_percent > 4 
		    	AND lead_payroll > 4 
		    	AND lead_price > 4)
	   		THEN 'Payroll and Price are Higer'
	   		WHEN gdp_value_percent > 4 
	   			AND lead_payroll > 4
	   		THEN 'Payroll is Higher'
	   		WHEN gdp_value_percent > 4 
	   			AND lead_price > 4
	   		THEN 'Price is Higher'
	   		WHEN gdp_value_percent > 4
	   			AND (lead_price
	   			OR lead_payroll) < 4
	   		THEN 'Has NO effect'
	   		ELSE '-'
	   END                                           AS previous_year_differences
FROM price_and_payroll
JOIN gdp_join
	ON common_year = `year`
WHERE common_year 
	 BETWEEN 2007 
		    AND 2018
	 AND gdp_value_percent > 4
GROUP BY common_year
ORDER BY common_year
;
