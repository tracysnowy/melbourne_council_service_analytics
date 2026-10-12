import pandas as pd
file_path = "data/raw/customer-service-requests-with-resolution-time.csv"

#load the dataset
df = pd.read_csv(file_path)

print("=" * 60)
print(f"DATASET OVERVIEW: {df.shape[0]:,} rows | {df.shape[1]} columns")
print("=" * 60)

#schema, column names, and missing values count
print("\nSCHEMA:")
print(df.dtypes)
print("\nCOLUMN NAMES:")
print(list(df.columns))
print("\nMISSING VALUES:")
print(df.isnull().sum())

#check distribution of DAYS_TO_COMPLETE
print("\n--- DISTRIBUTION OF DAYS_TO_COMPLETE: ----")
print(df['DAYS_TO_COMPLETE'].describe(percentiles=[0.25, 0.5, 0.75, 0.90, 0.95, 0.99]))

#check for negative days
negative_days = df[df['DAYS_TO_COMPLETE'] < 0]
print(f"\nNumber of records with negative DAYS_TO_COMPLETE: {negative_days.shape[0]}")

#unique categories to define SLA targets
print("\n--- SERVICE CATEGORIES: ----")
print(df['CATEGORY'].value_counts())