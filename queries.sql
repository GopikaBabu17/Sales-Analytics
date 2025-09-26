-- Created a duplicate table
SHOW VARIABLES LIKE 'local_infile';
DROP TABLE IF EXISTS transactions_raw;
CREATE TABLE transactions_raw (
  InvoiceNo   VARCHAR(20),
  StockCode   VARCHAR(20),
  Description TEXT,
  Quantity    VARCHAR(20),
  InvoiceDate VARCHAR(30),
  UnitPrice   VARCHAR(20),
  CustomerID  VARCHAR(20),
  Country     VARCHAR(100)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
-- Loading data
LOAD DATA LOCAL INFILE 'C:/Users/hp/Downloads/archive/data.csv'
INTO TABLE transactions_raw
CHARACTER SET latin1           -- <- key fix (file is Win-1252/Latin-1)
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'     -- if it errors, retry with '\n'
IGNORE 1 ROWS
(InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country);

select count(*) from transactions_raw;
-- Create actual table
DROP TABLE IF EXISTS transactions;
CREATE TABLE IF NOT EXISTS transactions (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  InvoiceNo    VARCHAR(20),
  StockCode    VARCHAR(20),
  Description  TEXT,
  Quantity     INT,
  InvoiceDate  DATETIME,
  UnitPrice    DECIMAL(10,2),
  CustomerID   VARCHAR(20),
  Country      VARCHAR(100)
) CHARACTER SET utf8mb4;

SET autocommit=0; SET UNIQUE_CHECKS=0; SET FOREIGN_KEY_CHECKS=0;

INSERT INTO transactions
(InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country)
SELECT
  TRIM(InvoiceNo),
  TRIM(StockCode),
  Description,
  CASE WHEN TRIM(Quantity) = '' THEN NULL ELSE CAST(Quantity AS SIGNED) END,
  COALESCE(
    STR_TO_DATE(InvoiceDate, '%m/%d/%Y %H:%i'),
    STR_TO_DATE(InvoiceDate, '%d/%m/%Y %H:%i')
  ),
  CASE WHEN TRIM(UnitPrice) = '' THEN NULL ELSE CAST(UnitPrice AS DECIMAL(10,2)) END,
  NULLIF(TRIM(CustomerID), ''),
  TRIM(Country)
FROM transactions_raw;

COMMIT; SET UNIQUE_CHECKS=1; SET FOREIGN_KEY_CHECKS=1;
-- Data Quality Checks
SELECT COUNT(*) rows_loaded FROM transactions;
SELECT MIN(InvoiceDate), MAX(InvoiceDate) FROM transactions;
select count(*) as missingid from transactions where id='' OR id IS NULL;
select count(*) as missingcustid from transactions where CustomerID='' OR CustomerID IS NULL;
SELECT COUNT(*) AS missing_descriptions
FROM transactions
WHERE Description IS NULL OR TRIM(Description) = '';
SELECT COUNT(*) AS missing_country
FROM transactions
WHERE Country IS NULL OR TRIM(Country) = '';
Select count(*) as missing from transactions where quantity<0;
select count(*) from transactions where UnitPrice<=0;
-- Duplicate rows (same invoice, product, quantity, price, date, customer, country)
SELECT InvoiceNo, StockCode, Quantity, UnitPrice, InvoiceDate, CustomerID, Country,
       COUNT(*) AS dup_count
FROM transactions
GROUP BY InvoiceNo, StockCode, Quantity, UnitPrice, InvoiceDate, CustomerID, Country
HAVING COUNT(*) > 1
ORDER BY dup_count DESC;
SELECT ROUND(SUM(Quantity * UnitPrice), 2) AS net_revenue
FROM transactions;
SELECT Country, COUNT(*) AS row_count
FROM transactions
GROUP BY Country
ORDER BY row_count DESC;

-- FIXING ISSUES
-- Null Descriptions updated as unknown product
UPDATE transactions
SET Description = 'Unknown Product'
WHERE Description IS NULL OR TRIM(Description) = '';
-- NULL CustomerID updated as Guest
UPDATE transactions
SET CustomerID = 'Guest'
WHERE CustomerID IS NULL OR TRIM(CustomerID) = '';
-- Flagged cases where quantity is less than 0
ALTER TABLE transactions ADD COLUMN IsReturn TINYINT(1);
UPDATE transactions SET IsReturn = (Quantity < 0);
-- delete rows where the unitprice was less than 0
DELETE FROM transactions WHERE UnitPrice <= 0;
-- removed duplicates
WITH dups AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY InvoiceNo, StockCode, Quantity, UnitPrice, InvoiceDate, CustomerID, Country
      ORDER BY id
    ) AS rn
  FROM transactions
)
DELETE t
FROM transactions t
JOIN dups d ON d.id = t.id
WHERE d.rn > 1;  
