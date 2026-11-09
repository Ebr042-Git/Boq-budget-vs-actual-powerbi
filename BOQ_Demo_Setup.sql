/* ============================================================
   BOQ_Demo - SYNTHETIC data only (no real company data)
   Run in SSMS against your local SQL Server (SQL 2016+).
   Safe to re-run: it drops and rebuilds the tables.
   Star schema: 4 dimensions + 3 facts + date table.
   ============================================================ */

IF DB_ID('BOQ_Demo') IS NULL CREATE DATABASE BOQ_Demo;
GO
USE BOQ_Demo;
GO

DROP TABLE IF EXISTS dbo.FactQuotation, dbo.FactActual, dbo.FactBOQ,
                     dbo.DimItem, dbo.DimVendor, dbo.DimTrade, dbo.DimProject, dbo.DimDate;
GO

/* ---------- DimDate (2024-01-01 to 2026-12-31) ---------- */
CREATE TABLE dbo.DimDate (
    DateKey    INT PRIMARY KEY,          -- yyyymmdd
    [Date]     DATE NOT NULL,
    [Year]     INT,
    MonthNo    INT,
    [MonthName] VARCHAR(10),
    YearMonth  CHAR(7),
    [Quarter]  VARCHAR(2)
);
GO
WITH d AS (
    SELECT CAST('2024-01-01' AS DATE) AS dt
    UNION ALL
    SELECT DATEADD(DAY, 1, dt) FROM d WHERE dt < '2026-12-31'
)
INSERT INTO dbo.DimDate
SELECT CONVERT(INT, CONVERT(CHAR(8), dt, 112)), dt, YEAR(dt), MONTH(dt),
       DATENAME(MONTH, dt), FORMAT(dt, 'yyyy-MM'), 'Q' + CAST(DATEPART(QUARTER, dt) AS VARCHAR(1))
FROM d OPTION (MAXRECURSION 0);
GO

/* ---------- DimProject ---------- */
CREATE TABLE dbo.DimProject (
    ProjectKey  INT PRIMARY KEY,
    ProjectName VARCHAR(60),
    City        VARCHAR(30),
    [Status]    VARCHAR(20),
    StartDate   DATE
);
INSERT INTO dbo.DimProject VALUES
(1,'Harbor Tower A','Dubai','In Progress','2025-01-15'),
(2,'Harbor Tower B','Dubai','In Progress','2025-02-10'),
(3,'Palm Residences','Dubai','Completed','2025-01-05'),
(4,'Desert Mall Phase 1','Sharjah','In Progress','2025-03-01'),
(5,'Desert Mall Phase 2','Sharjah','Planned','2025-05-20'),
(6,'Creek Office Park','Dubai','In Progress','2025-04-12'),
(7,'Falcon Hospital Wing','Abu Dhabi','In Progress','2025-06-01'),
(8,'Oasis School Campus','Abu Dhabi','Completed','2025-02-25'),
(9,'Sunrise Villas','Ajman','In Progress','2025-07-14'),
(10,'Logistics Hub North','Sharjah','Planned','2025-08-18');
GO

/* ---------- DimTrade ---------- */
CREATE TABLE dbo.DimTrade (
    TradeKey  INT PRIMARY KEY,
    TradeName VARCHAR(30)
);
INSERT INTO dbo.DimTrade VALUES
(1,'Civil'),(2,'Structural'),(3,'Finishes'),(4,'HVAC'),
(5,'Electrical'),(6,'Plumbing'),(7,'Fire Fighting'),(8,'External Works');
GO

/* ---------- DimVendor (3 per trade) ---------- */
CREATE TABLE dbo.DimVendor (
    VendorKey   INT IDENTITY(1,1) PRIMARY KEY,
    VendorName  VARCHAR(60),
    TradeKey    INT,
    VendorIndex INT                  -- 0,1,2 within trade
);
INSERT INTO dbo.DimVendor (VendorName, TradeKey, VendorIndex)
SELECT t.TradeName + ' Contractor ' + x.Letter, t.TradeKey, x.Idx
FROM dbo.DimTrade t
CROSS JOIN (VALUES ('A',0),('B',1),('C',2)) AS x(Letter, Idx);
GO

/* ---------- DimItem (15 BOQ items per trade) ---------- */
CREATE TABLE dbo.DimItem (
    ItemKey  INT IDENTITY(1,1) PRIMARY KEY,
    ItemName VARCHAR(80),
    TradeKey INT,
    Unit     VARCHAR(10),
    BaseRate DECIMAL(12,2)
);
INSERT INTO dbo.DimItem (ItemName, TradeKey, Unit, BaseRate)
SELECT t.TradeName + ' Item ' + CAST(n.n AS VARCHAR(3)),
       t.TradeKey,
       CASE n.n % 4 WHEN 0 THEN 'm2' WHEN 1 THEN 'm3' WHEN 2 THEN 'm' ELSE 'nos' END,
       20 + ((t.TradeKey * 37 + n.n * 53) % 480)
FROM dbo.DimTrade t
CROSS JOIN (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15)) AS n(n);
GO

/* ---------- FactBOQ: budget lines (about 70% of items per project) ---------- */
CREATE TABLE dbo.FactBOQ (
    BOQLineKey   INT IDENTITY(1,1) PRIMARY KEY,
    ProjectKey   INT,
    ItemKey      INT,
    Quantity     DECIMAL(14,2),
    BudgetRate   DECIMAL(12,2),
    BudgetAmount AS (Quantity * BudgetRate) PERSISTED
);
INSERT INTO dbo.FactBOQ (ProjectKey, ItemKey, Quantity, BudgetRate)
SELECT p.ProjectKey, i.ItemKey,
       50 + ABS(CHECKSUM(p.ProjectKey, i.ItemKey, 2)) % 2000,
       CAST(i.BaseRate * (0.90 + (ABS(CHECKSUM(p.ProjectKey, i.ItemKey, 3)) % 21) / 100.0) AS DECIMAL(12,2))
FROM dbo.DimProject p
CROSS JOIN dbo.DimItem i
WHERE ABS(CHECKSUM(p.ProjectKey, i.ItemKey, 1)) % 10 < 7;
GO

/* ---------- FactActual: 6 monthly progress entries per BOQ line ---------- */
CREATE TABLE dbo.FactActual (
    ActualKey  INT IDENTITY(1,1) PRIMARY KEY,
    BOQLineKey INT,
    ProjectKey INT,
    ItemKey    INT,
    VendorKey  INT,
    DateKey    INT,
    ActualQty  DECIMAL(14,2),
    ActualRate DECIMAL(12,2),
    ActualAmount AS (ActualQty * ActualRate) PERSISTED
);
INSERT INTO dbo.FactActual (BOQLineKey, ProjectKey, ItemKey, VendorKey, DateKey, ActualQty, ActualRate)
SELECT b.BOQLineKey, b.ProjectKey, b.ItemKey, v.VendorKey,
       CONVERT(INT, CONVERT(CHAR(8), DATEADD(MONTH, m.m, p.StartDate), 112)),
       CAST(b.Quantity / 6.0 * (0.80 + (ABS(CHECKSUM(b.BOQLineKey, m.m, 4)) % 41) / 100.0) AS DECIMAL(14,2)),
       CAST(b.BudgetRate * (0.92 + (ABS(CHECKSUM(b.BOQLineKey, m.m, 5)) % 21) / 100.0) AS DECIMAL(12,2))
FROM dbo.FactBOQ b
JOIN dbo.DimProject p ON p.ProjectKey = b.ProjectKey
JOIN dbo.DimItem i    ON i.ItemKey = b.ItemKey
JOIN dbo.DimVendor v  ON v.TradeKey = i.TradeKey AND v.VendorIndex = b.BOQLineKey % 3
CROSS JOIN (VALUES (0),(1),(2),(3),(4),(5)) AS m(m);
GO

/* ---------- FactQuotation: 3 vendor quotes per BOQ line ---------- */
CREATE TABLE dbo.FactQuotation (
    QuoteKey   INT IDENTITY(1,1) PRIMARY KEY,
    BOQLineKey INT,
    ProjectKey INT,
    ItemKey    INT,
    VendorKey  INT,
    DateKey    INT,
    QuotedRate DECIMAL(12,2)
);
INSERT INTO dbo.FactQuotation (BOQLineKey, ProjectKey, ItemKey, VendorKey, DateKey, QuotedRate)
SELECT b.BOQLineKey, b.ProjectKey, b.ItemKey, v.VendorKey,
       CONVERT(INT, CONVERT(CHAR(8), DATEADD(DAY, -30, p.StartDate), 112)),
       CAST(b.BudgetRate * (0.85 + (ABS(CHECKSUM(b.BOQLineKey, v.VendorKey, 6)) % 41) / 100.0) AS DECIMAL(12,2))
FROM dbo.FactBOQ b
JOIN dbo.DimProject p ON p.ProjectKey = b.ProjectKey
JOIN dbo.DimItem i    ON i.ItemKey = b.ItemKey
JOIN dbo.DimVendor v  ON v.TradeKey = i.TradeKey;
GO

/* ---------- Quick check ---------- */
SELECT 'DimProject' AS TableName, COUNT(*) AS Rows FROM dbo.DimProject UNION ALL
SELECT 'DimItem', COUNT(*) FROM dbo.DimItem UNION ALL
SELECT 'DimVendor', COUNT(*) FROM dbo.DimVendor UNION ALL
SELECT 'FactBOQ', COUNT(*) FROM dbo.FactBOQ UNION ALL
SELECT 'FactActual', COUNT(*) FROM dbo.FactActual UNION ALL
SELECT 'FactQuotation', COUNT(*) FROM dbo.FactQuotation;
