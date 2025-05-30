-- Check column types
SELECT column_name,
    data_type
FROM information_schema.columns
WHERE table_name = 'ds_salaries';
-- Overview the data
SELECT *
FROM ds_salaries
LIMIT 50;

-- First we will explore job category in relation to the salary
-- select avg and median salary per job category
-- rank job category based on both mean and median salaries
-- find difference between place n and n-1 (also for both mean and median)
WITH first_CTE AS(
    SELECT job_category
        ,CAST(AVG(salary_in_usd) AS INT) AS avg_salary
        ,PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY salary_in_usd) AS median_salary
        ,RANK() OVER (ORDER BY AVG(salary_in_usd) DESC) AS rank_avg_salary
        ,RANK() OVER (ORDER BY PERCENTILE_DISC(0.5) 
                WITHIN GROUP(ORDER BY salary_in_usd) DESC
            ) AS rank_median_salary
    FROM ds_salaries
    GROUP BY job_category
)
SELECT *
    ,ABS(LAG(avg_salary, 1) 
        OVER(ORDER BY rank_avg_salary) - avg_salary
    ) AS diff_salary_by_avg
    ,ABS(LAG(median_salary, 1) 
        OVER(ORDER BY rank_median_salary) - median_salary
    ) AS diff_salary_by_mean
FROM first_CTE;
-- Key takeways
-- ML/AI has a higher mean salary than Data Analyst category, but a lower median
-- Median salary for Leadership positions is higher than the mean, that's unexpected. We should look at what job titles are in this category.


-- Second task - explore impact of work expirience/company size/remote status to the salary
-- Expectations:
-- The more time you spend in office - the higher the salary
-- Work expirience also has a positive correlation with salary
-- Small companies probably have smaller salaries, but mid and big companies don't differ as much
SELECT remote
    , CAST(AVG(salary_in_usd) AS INT) AS avg_salary
    , PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY salary_in_usd) AS median_salary
FROM ds_salaries
GROUP BY remote;
-- An unexpected outcome. Remote employees have both highest mean and median salaries
-- followed by Onsite and Hybrid

SELECT experience_level
    , CAST(AVG(salary_in_usd) AS INT) AS avg_salary
    , PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY salary_in_usd) AS median_salary
FROM ds_salaries
GROUP BY experience_level;
-- Everything came as expected, 
-- and worth noting that mean and median salaries don't really differ for all experience levels 

SELECT company_size
    , CAST(AVG(salary_in_usd) AS INT) AS avg_salary
    , PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY salary_in_usd) AS median_salary
FROM ds_salaries
GROUP BY company_size;
-- The results are almost like we predicted
-- But medium companies have even higher median salaries than large companies do


-- Our third task is to find impact of emloyee location on the salarie
-- Because remote workers are not affected by their location, we can ignore them
WITH no_remote_CTE AS (
    SELECT employee_continent, salary_in_usd
    FROM ds_salaries
    WHERE remote <> 'Remote'
)
SELECT employee_continent
    , CAST(AVG(salary_in_usd) AS INT) AS avg_salary
    , PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY salary_in_usd) AS median_salary
FROM no_remote_CTE
GROUP BY employee_continent
ORDER BY AVG(salary_in_usd) DESC;
-- Unexpectedly, Africa is higher on the list than Europe and Asia
-- If we check with remote workers, Africa will be last
SELECT employee_continent
    , CAST(AVG(salary_in_usd) AS INT) AS avg_salary
    , PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY salary_in_usd) AS median_salary
FROM ds_salaries
GROUP BY employee_continent
ORDER BY AVG(salary_in_usd) DESC;

-- In that case we should look at all employees in Africa
SELECT employee_continent, remote, job_title, job_category, salary_in_usd
FROM ds_salaries
WHERE employee_continent ='Africa';
-- Aha! we can see that africa has 5 employees total, 4/5 are remote workers with low salary
-- And only one 1 out of all employees is not remote,
-- and he's also the only one with a high salary. But is it an outlier?

WITH percentile_CTE AS (
    SELECT employee_continent
        , PERCENTILE_CONT(0.75) WITHIN GROUP(ORDER BY salary_in_usd) AS third_q
        , PERCENTILE_CONT(0.25) WITHIN GROUP(ORDER BY salary_in_usd) AS first_q
    FROM ds_salaries
    WHERE employee_continent= 'Africa'
    GROUP BY employee_continent
)
SELECT  employee_continent, remote, salary_in_usd
    , CASE WHEN salary_in_usd> third_q+1.5*(third_q-first_q) THEN 'Outlier' ELSE 'Normal' END AS outlier
FROM ds_salaries
JOIN percentile_CTE
USING(employee_continent)
WHERE employee_continent='Africa';
-- Due to a small dataset, we can't be certain
-- this data point falls within q_3+1.5iqr
-- but but we'll assume It's an outlier 


-- Task number 4 is to check saalry trends over years
-- I'd be interested in looking at trends per job category
-- And I would want to compare n year value with n-1 year value
SELECT job_category, work_year, AVG(salary_in_usd) AS avg_salary
FROM ds_salaries
GROUP BY job_category, work_year
ORDER BY job_category, work_year;
-- In this general query, we can see that there are no value for Data Leadership for year 2020

WITH salary_CTE AS (
    SELECT job_category, work_year
        , AVG(salary_in_usd) AS avg_salary
        , LAG(AVG(salary_in_usd),1,AVG(salary_in_usd)) OVER(PARTITION BY job_category ORDER BY work_year) AS past_avg_salary
    FROM ds_salaries
    GROUP BY job_category, work_year
)
SELECT job_category,work_year
    , CAST(avg_salary AS INT) AS current_salary
    , CAST(past_avg_salary AS INT) AS previous_salary
    , CAST(avg_salary-past_avg_salary AS INT) AS yearly_change,
    CASE
        WHEN past_avg_salary IS NULL THEN NULL
        ELSE ROUND((avg_salary - past_avg_salary) / past_avg_salary * 100, 1) 
    END AS percent_change
FROM salary_CTE;
-- We can see that only a few times mean salary has decreased over time

-- Now I'll save some views for further BI visualization
CREATE VIEW salary_by_location AS
SELECT 
    employee_continent,
    remote,
    COUNT(*) as employee_count,
    CAST(AVG(salary_in_usd) AS INT) as avg_salary,
    CAST(PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY salary_in_usd) AS INT) as median_salary
FROM ds_salaries
GROUP BY employee_continent, remote
HAVING COUNT(*) >= 3  -- Filter out small samples like Africa
ORDER BY avg_salary DESC;

CREATE VIEW salary_trends_yearly AS
WITH salary_CTE AS (
    SELECT job_category, work_year
        , AVG(salary_in_usd) AS avg_salary
        , LAG(AVG(salary_in_usd),1,AVG(salary_in_usd)) OVER(PARTITION BY job_category ORDER BY work_year) AS past_avg_salary
    FROM ds_salaries
    GROUP BY job_category, work_year
)
SELECT job_category,work_year
    , CAST(avg_salary AS INT) AS current_salary
    , CAST(past_avg_salary AS INT) AS previous_salary
    , CAST(avg_salary-past_avg_salary AS INT) AS yearly_change,
    CASE
        WHEN past_avg_salary IS NULL THEN NULL
        ELSE ROUND((avg_salary - past_avg_salary) / past_avg_salary * 100, 1) 
    END AS percent_change
FROM salary_CTE;


CREATE VIEW salary_by_job_category AS
SELECT 
    job_category,
    COUNT(*) as employee_count,
    CAST(AVG(salary_in_usd) AS INT) as avg_salary,
    CAST(PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY salary_in_usd) AS INT) as median_salary,
    MIN(salary_in_usd) as min_salary,
    MAX(salary_in_usd) as max_salary,
    CAST(PERCENTILE_DISC(0.25) WITHIN GROUP(ORDER BY salary_in_usd) AS INT) as q1_salary,
    CAST(PERCENTILE_DISC(0.75) WITHIN GROUP(ORDER BY salary_in_usd) AS INT) as q3_salary
FROM ds_salaries
GROUP BY job_category;

