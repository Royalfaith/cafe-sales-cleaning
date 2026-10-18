-- Cafe sales cleaning pipeline (SQLite syntax)
-- Input : raw_cafe  (all columns loaded as TEXT from dirty_cafe_sales.csv)
-- Output: cafe_clean (10,000 rows kept, nothing deleted; unrecoverable values stay NULL or 'Unknown')

-- STEP 1: Standardise every kind of "missing" (blank, ERROR, UNKNOWN) to NULL
DROP TABLE IF EXISTS step1;
CREATE TABLE step1 AS
SELECT
  TRIM("Transaction ID") AS transaction_id,
  CASE WHEN TRIM(Item)               IN ('','ERROR','UNKNOWN') THEN NULL ELSE TRIM(Item) END               AS item,
  CASE WHEN TRIM(Quantity)           IN ('','ERROR','UNKNOWN') THEN NULL ELSE TRIM(Quantity) END           AS quantity,
  CASE WHEN TRIM("Price Per Unit")   IN ('','ERROR','UNKNOWN') THEN NULL ELSE TRIM("Price Per Unit") END   AS price_per_unit,
  CASE WHEN TRIM("Total Spent")      IN ('','ERROR','UNKNOWN') THEN NULL ELSE TRIM("Total Spent") END      AS total_spent,
  CASE WHEN TRIM("Payment Method")   IN ('','ERROR','UNKNOWN') THEN NULL ELSE TRIM("Payment Method") END   AS payment_method,
  CASE WHEN TRIM(Location)           IN ('','ERROR','UNKNOWN') THEN NULL ELSE TRIM(Location) END           AS location,
  CASE WHEN TRIM("Transaction Date") IN ('','ERROR','UNKNOWN') THEN NULL ELSE TRIM("Transaction Date") END AS transaction_date
FROM raw_cafe;

-- STEP 2: Convert text to proper types (integer, decimal, valid date)
DROP TABLE IF EXISTS step2;
CREATE TABLE step2 AS
SELECT
  transaction_id,
  item,
  CAST(quantity AS INTEGER)       AS quantity,
  CAST(price_per_unit AS REAL)    AS price_per_unit,
  CAST(total_spent AS REAL)       AS total_spent,
  payment_method,
  location,
  CASE WHEN date(transaction_date) = transaction_date THEN transaction_date END AS transaction_date
FROM step1;

-- STEP 3: Recover numbers with arithmetic (Total = Quantity x Price)
DROP TABLE IF EXISTS step3;
CREATE TABLE step3 AS
SELECT
  transaction_id,
  item,
  COALESCE(quantity,
    CASE WHEN price_per_unit > 0 AND total_spent IS NOT NULL
          AND ABS(total_spent / price_per_unit - ROUND(total_spent / price_per_unit)) < 1e-9
         THEN CAST(ROUND(total_spent / price_per_unit) AS INTEGER) END)        AS quantity,
  COALESCE(price_per_unit,
    CASE WHEN quantity > 0 AND total_spent IS NOT NULL THEN total_spent / quantity END) AS price_per_unit,
  COALESCE(total_spent, quantity * price_per_unit)                               AS total_spent,
  payment_method,
  location,
  transaction_date
FROM step2;

-- STEP 4: Recover from the menu. Each item has one fixed price in this data,
--         so price gives back the item when only one item sells at that price,
--         and item gives back a missing price. Then repeat the arithmetic.
DROP TABLE IF EXISTS menu;
CREATE TABLE menu AS
SELECT item, MIN(price_per_unit) AS menu_price
FROM step3 WHERE item IS NOT NULL AND price_per_unit IS NOT NULL
GROUP BY item HAVING COUNT(DISTINCT price_per_unit) = 1;

DROP TABLE IF EXISTS unique_price;
CREATE TABLE unique_price AS
SELECT menu_price, MIN(item) AS item
FROM menu GROUP BY menu_price HAVING COUNT(*) = 1;

DROP TABLE IF EXISTS step4a;
CREATE TABLE step4a AS
SELECT
  s.transaction_id,
  COALESCE(s.item, (SELECT u.item FROM unique_price u WHERE u.menu_price = s.price_per_unit)) AS item,
  s.quantity,
  COALESCE(s.price_per_unit, (SELECT m.menu_price FROM menu m WHERE m.item = s.item))         AS price_per_unit,
  s.total_spent, s.payment_method, s.location, s.transaction_date
FROM step3 s;

DROP TABLE IF EXISTS step4;
CREATE TABLE step4 AS
SELECT
  transaction_id, item,
  COALESCE(quantity,
    CASE WHEN price_per_unit > 0 AND total_spent IS NOT NULL
          AND ABS(total_spent / price_per_unit - ROUND(total_spent / price_per_unit)) < 1e-9
         THEN CAST(ROUND(total_spent / price_per_unit) AS INTEGER) END) AS quantity,
  price_per_unit,
  COALESCE(total_spent, quantity * price_per_unit)                      AS total_spent,
  payment_method, location, transaction_date
FROM step4a;

-- STEP 5: Label unrecoverable categories honestly instead of guessing
DROP TABLE IF EXISTS step5;
CREATE TABLE step5 AS
SELECT transaction_id, item, quantity, price_per_unit, total_spent,
  COALESCE(payment_method,'Unknown') AS payment_method,
  COALESCE(location,'Unknown')       AS location,
  transaction_date
FROM step4;

-- STEP 6: Integrity checks (all should return 0 rows)
--   duplicate IDs:
--     SELECT transaction_id, COUNT(*) FROM step5 GROUP BY 1 HAVING COUNT(*) > 1;
--   malformed IDs:
--     SELECT * FROM step5 WHERE transaction_id NOT GLOB 'TXN_[0-9][0-9][0-9][0-9][0-9][0-9][0-9]';
--   arithmetic that does not hold:
--     SELECT * FROM step5 WHERE quantity IS NOT NULL AND price_per_unit IS NOT NULL
--       AND total_spent IS NOT NULL AND ABS(total_spent - quantity * price_per_unit) > 0.001;

-- STEP 7: Final table with a completeness flag for analysis
DROP TABLE IF EXISTS cafe_clean;
CREATE TABLE cafe_clean AS
SELECT *,
  CASE WHEN item IS NOT NULL AND quantity IS NOT NULL AND price_per_unit IS NOT NULL
        AND total_spent IS NOT NULL AND transaction_date IS NOT NULL THEN 1 ELSE 0 END AS is_complete
FROM step5;
