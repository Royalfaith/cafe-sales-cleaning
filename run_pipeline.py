"""Runs cafe_cleaning.sql on dirty_cafe_sales.csv and writes cafe_clean.csv.
Needs only Python 3 and pandas. Put this file, the SQL file and the raw CSV in one folder."""
import sqlite3
import pandas as pd

con = sqlite3.connect(":memory:")
pd.read_csv("dirty_cafe_sales.csv", dtype=str, keep_default_na=False).to_sql("raw_cafe", con, index=False)
con.executescript(open("cafe_cleaning.sql").read())
out = pd.read_sql("SELECT * FROM cafe_clean", con)
out.to_csv("cafe_clean.csv", index=False)
print(len(out), "rows written;", int(out["is_complete"].sum()), "rows complete")
