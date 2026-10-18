# Cafe sales: cleaning a messy dataset with SQL

A seven-step SQL pipeline that turns 10,000 error-filled cafe sales rows into a table that is safe to analyse. No rows are deleted. Values that cannot be recovered stay NULL or are labelled Unknown, so nothing is guessed.

## The problem

The raw file has 10,000 transactions and 8 columns. Missing information appears in three disguises: an empty cell, the word `ERROR`, and the word `UNKNOWN`. Across the seven fields that matter there are **10,082 missing or invalid cells**, and only **7,382 rows (73.8%)** have a valid item, quantity, price, total and date.

| Column | Bad cells in raw data |
|---|---|
| Item | 969 |
| Quantity | 479 |
| Price Per Unit | 533 |
| Total Spent | 502 |
| Payment Method | 3,178 |
| Location | 3,961 |
| Transaction Date | 460 |

## Results

| Measure | Before | After |
|---|---|---|
| Rows | 10,000 | 10,000 (none deleted) |
| Rows with item, quantity, price, total and date all valid | 7,382 (73.8%) | 9,064 (90.6%) |
| Missing item | 969 | 480 |
| Missing quantity | 479 | 23 |
| Missing price | 533 | 6 |
| Missing total | 502 | 23 |
| Rows where quantity x price does not equal total | not testable | 0 of 9,974 checked |

Of the 10,082 bad cells: **1,951 were recovered**, **7,139 payment and location gaps were labelled Unknown**, and **992 remain NULL** because no other column could supply them (460 dates, 480 items, 23 quantities, 23 totals, 6 prices).

## The seven steps

1. **Standardise missing values.** Blank, `ERROR` and `UNKNOWN` all become NULL, so there is one consistent way to find gaps.
2. **Convert types.** Quantity to integer, price and total to decimal, date to a validated date. No invalid date strings were found, only missing ones.
3. **Recover numbers with arithmetic.** Total = quantity x price, so any one missing value can be rebuilt from the other two. Quantity is only recovered when the division gives a whole number. This recovered 1,398 cells.
4. **Recover from the menu.** Each item sells at one fixed price in this data (Coffee 2.0, Tea 1.5, Cookie 1.0, Salad 5.0, Cake 3.0, Juice 3.0, Sandwich 4.0, Smoothie 4.0). A price of 1.0, 1.5, 2.0 or 5.0 identifies exactly one item. A known item gives back a missing price. The arithmetic from step 3 then runs again. This recovered 553 more cells.
5. **Label unrecoverable categories.** Payment method and location cannot be derived from anything else, so NULLs become `Unknown` instead of being guessed.
6. **Integrity checks.** No duplicate transaction IDs, no malformed IDs, and quantity x price equals total on every row where all three exist.
7. **Final table.** `cafe_clean` keeps all 10,000 rows and adds an `is_complete` flag, so analysts can choose to filter instead of the pipeline deciding for them.

## Decisions worth knowing

- **Rows were not deleted.** Dropping rows with any gap would remove 69% of the data. Flagging keeps the information that is still valid.
- **Items were not guessed when the price was ambiguous.** A price of 3.0 fits Cake and Juice, and 4.0 fits Sandwich and Smoothie. Those items stay NULL. This is why 480 items remain missing.
- **Dates were not filled.** Nothing else in a row says when it happened, and inventing dates would corrupt any trend analysis.
- **Unknown is a label, not a value.** Payment and location totals should be reported with the Unknown share shown.

## Files

| File | What it is |
|---|---|
| `cafe_cleaning.sql` | The full pipeline (SQLite syntax) |
| `run_pipeline.py` | Runs the SQL on the raw CSV and writes the clean file |
| `dirty_cafe_sales.csv` | Raw input, unchanged |
| `cafe_clean.csv` | Output of the pipeline |

## How to run

Put the four files in one folder, then:

```
pip install pandas
python run_pipeline.py
```

You can also open `dirty_cafe_sales.csv` in DB Browser for SQLite, import it as a table named `raw_cafe` with every column as text, and run `cafe_cleaning.sql`.

## Limitations

- Price-to-item recovery relies on every item having one fixed price in this dataset. A real cafe with promotions or price changes would need a dated price table instead.
- 4.8% of items and 4.6% of dates are still missing, so item-level and monthly analysis should use `is_complete = 1` or report the gaps.
