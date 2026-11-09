# DAX measures

All measures live in one table called `_Measures` so they are easy to find.
Facts are never summed by dragging columns into visuals; every number comes from an explicit measure.

## Core measures

```DAX
Budget Amount =
IF (
    ISFILTERED ( DimDate ),
    BLANK (),
    SUM ( FactBOQ[BudgetAmount] )
)
```

```DAX
Actual Amount =
SUM ( FactActual[ActualAmount] )
```

```DAX
Variance =
IF (
    ISBLANK ( [Budget Amount] ),
    BLANK (),
    [Actual Amount] - [Budget Amount]
)
```

```DAX
Variance% =
DIVIDE ( [Variance], [Budget Amount] )
```

```DAX
Detail Title =
"Project Detail: " & SELECTEDVALUE ( DimProject[ProjectName], "All Projects" )
```

## Why the measures are written this way

**Budget Amount returns BLANK when a date filter is active.**
`FactBOQ` has no date column (budget is set per project and item, once). A month filter cannot reach it,
so without the `ISFILTERED` guard every month would show the full 199.6M budget. That number is wrong,
and a reader would think the budget is 199.6M per month. A blank is more honest than a wrong number.

**Variance has an `ISBLANK` guard.**
`Actual - BLANK` is treated as `Actual - 0`, which would show the whole actual cost as "variance"
in any month. The guard keeps Variance blank wherever Budget is blank.

**Variance% uses `DIVIDE`, not `/`.**
`DIVIDE` returns BLANK instead of an error when the budget is zero or blank.

**Sign convention:** Variance = Actual - Budget. Positive means over budget (bad), negative means a saving.

**Detail Title** feeds the title of the drill-through page. With a project selected it reads
"Project Detail: Harbor Tower A"; with no project it falls back to "All Projects".

## Reconciliation check

| Check | Value |
|---|---|
| Sum of trade budgets = Total row | 199,598,464 |
| Sum of trade actuals = Total row | 203,500,304 |
| Variance | 3,901,840 (1.95%) |

The same totals come out of `SELECT SUM(BudgetAmount) FROM dbo.FactBOQ` in SQL.
