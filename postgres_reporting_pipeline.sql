-- =======================================================================================================================
-- B. USER-DEFINED FUNCTION
-- =======================================================================================================================
-- B.  Provide original code for function(s) in text format that perform the transformation(s) you identified in part A4.

-- Create or Replace function simply creates a new or updates a exsisting function. 
CREATE OR REPLACE FUNCTION get_return_status(p_return_date TIMESTAMP)
	-- Function returns a character string with a max length of 20 Characters
	RETURNS VARCHAR(20)
	-- Procedural Lanaguuage 
	LANGUAGE plpgsql
AS
$$
BEGIN
	-- This if statement checks for rentals that have not been returned
	-- NULL just means that the value is empty therefore it has not been returned.
    IF p_return_date IS NULL THEN
        RETURN 'Not Returned';
    ELSE
        RETURN 'Returned';
    END IF;
END;
$$;

-- =======================================================================================================================
-- TESTING PART B: 
-- =======================================================================================================================


SELECT
    get_return_status(NOW()) AS test_returned,
    get_return_status(NULL) AS test_not_returned;

-- =======================================================================================================================
-- C. CREATE DETAILED AND SUMMARY TABLES
-- =======================================================================================================================
-- Drop the tables if they already exist
-- Cascade automatically removes any linked dependencies, like foreign keys or triggers
-- Added these two lines so the script can be reran without "already exists" errors. 
DROP TABLE IF EXISTS customer_rental_detail CASCADE;
DROP TABLE IF EXISTS customer_rental_summary CASCADE;

CREATE TABLE customer_rental_detail (
    customer_id   INTEGER,
    first_name    VARCHAR(45),
    last_name     VARCHAR(45),
    rental_id     INTEGER PRIMARY KEY,
    rental_date   TIMESTAMP WITH TIME ZONE,
    return_date   TIMESTAMP WITH TIME ZONE,
    title         VARCHAR(255),
    amount        DECIMAL(7, 2),
    return_status VARCHAR(20)
);

-- TESTING=================================================================================================================
SELECT * FROM customer_rental_detail

-- Creating a summary table as opposed to my detailed table shown above.
CREATE TABLE customer_rental_summary (
    customer_id   INTEGER PRIMARY KEY,
    first_name    VARCHAR(45),
    last_name     VARCHAR(45),
    total_rentals INTEGER,
    total_revenue DECIMAL(10, 2) 
);

-- TESTING================================================================================================================
SELECT * FROM customer_rental_summary


-- =======================================================================================================================
-- D. EXTRACT RAW DATA FOR DETAILED REPORT
-- =======================================================================================================================
-- D.  Provide an original SQL query in a text format that will extract the raw data needed for the detailed 
--     section of your report from the source database.

-- Now that I've created the above table, I will insert data into it via INSERT INTO.
INSERT INTO customer_rental_detail (
	-- These are the columns that we will populate. 
    customer_id,
    first_name,
    last_name,
    rental_id,
    rental_date,
    return_date,
    title,
    amount,
    return_status
)
SELECT 
	-- Because we are dealing with mutiple tables i need to specify via "c.___"
	-- Grabbing data from customer, rental and film tables.
    c.customer_id,
    c.first_name,
    c.last_name,
    r.rental_id,
    r.rental_date,
    r.return_date,
    f.title,
	-- This is a way to avoid trying to add NULL when I really want to add 0.00.
    COALESCE(placeholder.amount, 0.00) AS amount,
	-- I'm calling the function I created in part B.
    get_return_status(r.return_date) AS return_status
-- Assigning tables with an alias starting with the first letter per convention. 
FROM customer c
JOIN rental r 
	-- "ON c.customer_id = r.customer_id" matches records where the customer ID is identical across both tables.
    ON c.customer_id = r.customer_id
JOIN inventory i 
    ON r.inventory_id = i.inventory_id
JOIN film f
    ON i.film_id = f.film_id
	-- LEFT JOIN keeps all rows from the existing result above,
	-- This includes every rental, even if no matching payment exists.
	LEFT JOIN (
	-- From the payment table give me the rental_id
    SELECT 
        rental_id, 
		-- Add all payment amounts for each rental and name the result "amount".
        SUM(amount) AS amount
	-- The data is coming from the payment table. Specifically grab the rental_id's
    FROM payment
	-- Only use payment records that actually have a rental ID.
	-- Essentially excluding any NULL values that are found in rental_id column.
    WHERE rental_id IS NOT NULL
	-- Here I put all payment rows belonging to the same rental together.
    GROUP BY rental_id
  -- Closing out the subquery and storing temporary result in "placeholder".
) placeholder 
	-- Match the rental transaction to its consolidated payments using rental_id.
    ON r.rental_id = placeholder.rental_id
-- Prevents duplicate key errors if the script is run multiple times against the table.
ON CONFLICT (rental_id) DO NOTHING;

-- =======================================================================================================================
-- TESTING PART D: 
-- =======================================================================================================================

SELECT
    rental_id,
    customer_id,
    first_name,
    last_name,
    title,
    amount
FROM customer_rental_detail
WHERE amount > 0
ORDER BY amount DESC
LIMIT 100;


-- =======================================================================================================================
-- E. TRIGGER
-- =======================================================================================================================

-- Part E can be broken down into 2 parts. The trigger function and the trigger itself
-- Part 1: The Trigger function 
-- Here I am naming the trigger "update_customer_summary" and it takes no inputs (that is the reason for empty parentheses).
CREATE OR REPLACE FUNCTION update_customer_summary()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
BEGIN
	-- INSERT INTO will target the customer_rental_summary that I created in part c.
    INSERT INTO customer_rental_summary (
        customer_id,
        first_name,
        last_name,
        total_rentals,
        total_revenue
    )
    VALUES (
		-- "NEW" just refers to the row that just entered the table. Opposed to "OLD" representing the existing row before a change.
		-- I'm adding the following values into the five columns above. 
        NEW.customer_id,
        NEW.first_name,
        NEW.last_name,
		-- For a new customer add 1 to start 
        1,
        NEW.amount
    )

	-- If the customer_id already exsists do the following
    ON CONFLICT (customer_id)
	-- The insert operation turn into this "UPDATE" operation
    DO UPDATE SET
		-- This is the statement where I add a 1 for evreytime I encounter a pre existing customer.
        total_rentals = customer_rental_summary.total_rentals + 1,
		-- Adding the new "amount" to the total revenue to effectively get the total revneue amount if the customer has multiple rentals. 
        total_revenue = customer_rental_summary.total_revenue + NEW.amount;

    RETURN NEW;

END;
$$;

-- Part 2: Create the trigger that automatically runs the function
-- whenever a new row is inserted into the detailed report.
DROP TRIGGER IF EXISTS customer_rental_summary_trigger
ON customer_rental_detail;

CREATE TRIGGER customer_rental_summary_trigger
AFTER INSERT ON customer_rental_detail
FOR EACH ROW
EXECUTE FUNCTION update_customer_summary();

-- =======================================================================================================================
-- TESTING PART E: 
-- =======================================================================================================================

-- TEST 1: Check the summary table before inserting new rentals.

SELECT *
FROM customer_rental_summary
WHERE customer_id = 1;

-- Insert two test rentals for the same customer.

BEGIN;

INSERT INTO customer_rental_detail (
    customer_id,
    first_name,
    last_name,
    rental_id,
    rental_date,
    return_date,
    title,
    amount,
    return_status
)
VALUES
    (1, 'Test', 'Customer', 999999, NOW(), NULL, 'Trigger Test 1', 5.00, get_return_status(NULL)),
    (1, 'Test', 'Customer', 999998, NOW(), NULL, 'Trigger Test 2', 7.00, get_return_status(NULL));

-- TEST 2: Check the summary table after inserting the rentals.
-- The trigger should have automatically created a summary record
-- showing 2 rentals and $12.00 in total revenue.

SELECT *
FROM customer_rental_summary
WHERE customer_id = 1;


-- Remove the temporary test data.

ROLLBACK;

-- =======================================================================================================================
-- F.
-- =======================================================================================================================

-- Part F: Provide an original stored procedure in a text format that can be used to refresh the data in both the detailed table and summary table. 
--         The procedure should clear the contents of the detailed table and summary table and perform the raw data extraction from part D.
--         1.  Identify a relevant job scheduling tool that can be used to automate the stored procedure.

CREATE OR REPLACE PROCEDURE refresh_customer_rental_reports()
LANGUAGE plpgsql
AS
$$
BEGIN

    -- Clear tables
    TRUNCATE TABLE customer_rental_detail;
    TRUNCATE TABLE customer_rental_summary;

    -- Rebuild the detailed report using the same source extraction
    -- created in Part D.
    INSERT INTO customer_rental_detail (
        customer_id,
        first_name,
        last_name,
        rental_id,
        rental_date,
        return_date,
        title,
        amount,
        return_status
    )
    SELECT 
        c.customer_id,
        c.first_name,
        c.last_name,
        r.rental_id,
        r.rental_date,
        r.return_date,
        f.title,
        COALESCE(placeholder.amount, 0.00) AS amount,
        get_return_status(r.return_date) AS return_status
    FROM customer c
    JOIN rental r 
        ON c.customer_id = r.customer_id
    JOIN inventory i 
        ON r.inventory_id = i.inventory_id
    JOIN film f
        ON i.film_id = f.film_id
    LEFT JOIN (
        SELECT 
            rental_id,
            SUM(amount) AS amount
        FROM payment
        WHERE rental_id IS NOT NULL
        GROUP BY rental_id
	) placeholder 
	        ON r.rental_id = placeholder.rental_id;

END;
$$;

-- =======================================================================================================================
-- TESTING PART F: 
-- =======================================================================================================================

-- Refresh both report tables
CALL refresh_customer_rental_reports();


-- Rebuild the detail table
SELECT COUNT(*) AS detail_rows
FROM customer_rental_detail;

-- Display customer report
SELECT
    customer_id,
    first_name,
    last_name,
    total_rentals,
    total_revenue
FROM customer_rental_summary
ORDER BY total_revenue DESC;

-- F1: pg_cron is an ideal tool for this database. It can be ran directly inside of PostreSQL.
--     This gives you a way to automate refresh at a time during non peak hours. 


