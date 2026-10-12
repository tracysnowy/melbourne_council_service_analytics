import os
import sqlite3
import pandas as pd

#File paths
PROCESSED_FILE_PATH = "data/processed/customer_requests_cleaned.csv"
DB_PATH = "data/melbourne_council.db"

def build_star_schema():
    print("=" * 60)
    print("BUILDING STAR SCHEMA & SQLITE DATABASE...")
    print("=" * 60)

    #Load the processed dataset
    print("\nLoading processed dataset...")
    df = pd.read_csv(PROCESSED_FILE_PATH)
    print(f"Loaded dataset with {df.shape[0]:,} rows and {df.shape[1]} columns successfully.")

    #Ensure datetime format
    df['date_received'] = pd.to_datetime(df['date_received'])
    df['date_completed'] = pd.to_datetime(df['date_completed'])

    #Build Dimesion Tables
    print("\nBuilding dimension tables...")

    #Dim_Suburb
    unique_suburbs = sorted(df['suburb'].unique())
    dim_suburb = pd.DataFrame({
        'suburb_id': range(1, len(unique_suburbs) + 1),
        'suburb_name': unique_suburbs
    })

    #Dim_Category (category + service_desc + sla_target_days)
    dim_category = (
        df[['category', 'service_desc', 'sla_target_days']]
        .drop_duplicates()
        .reset_index(drop=True)
    )
    dim_category['category_id'] = range(1, len(dim_category) + 1)
    #Reorder columns
    dim_category = dim_category[['category_id', 'category', 'service_desc', 'sla_target_days']]

    #Dim_Date (covering the entire range ofdate_received)
    min_date = df['date_received'].min()
    max_date = df['date_received'].max()
    date_range = pd.date_range(start=min_date, end=max_date, freq='D')

    dim_date = pd.DataFrame({'full_date': date_range})
    dim_date['date_key'] = dim_date['full_date'].dt.strftime('%Y%m%d').astype(int)
    dim_date['year'] = dim_date['full_date'].dt.year
    dim_date['quarter'] = 'Q' + dim_date['full_date'].dt.quarter.astype(str)
    dim_date['month'] = dim_date['full_date'].dt.month
    dim_date['month_name'] = dim_date['full_date'].dt.strftime('%B')
    dim_date['day'] = dim_date['full_date'].dt.day
    dim_date['day_of_week'] = dim_date['full_date'].dt.strftime('%A')
    dim_date['is_weekend'] = dim_date['full_date'].dt.weekday.isin([5, 6]).astype(int)
    dim_date['full_date'] = dim_date['full_date'].dt.strftime('%Y-%m-%d')

    #Build Fact Table
    print("\nBuilding Fact table (fact_service_requests)...")

    #Map foreign keys back to fact table
    fact_df = df.copy()

    #Map suburb_id
    suburb_map = dict(zip(dim_suburb['suburb_name'], dim_suburb['suburb_id']))
    fact_df['suburb_id'] = fact_df['suburb'].map(suburb_map)

    #Map category_id
    cat_merged = fact_df.merge(
        dim_category[['category', 'service_desc', 'category_id']],
        on=['category', 'service_desc'],
        how='left'
    )
    fact_df['category_id'] = cat_merged['category_id']

    #Map date_key
    fact_df['received_date_key'] = fact_df['date_received'].dt.strftime('%Y%m%d').astype(int)

    #Primary key for fact table
    fact_df['request_id'] = range(1, len(fact_df) + 1)

    #Select columns for fact table
    fact_service_requests = fact_df[[
        'request_id',
        'suburb_id',
        'category_id',
        'received_date_key',
        'request_status',
        'days_to_complete',
        'sla_target_days',
        'sla_status',
        'is_sla_breached'
    ]].copy()

    #Load into SQLite database
    print("\nCreating SQLite database and loading tables...")
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    #Enable foreign keys
    cursor.execute("PRAGMA foreign_keys = ON;")

    #Write tables to SQLite
    dim_suburb.to_sql('dim_suburb', conn, if_exists='replace', index=False)
    dim_category.to_sql('dim_category', conn, if_exists='replace', index=False)
    dim_date.to_sql('dim_date', conn, if_exists='replace', index=False)
    fact_service_requests.to_sql('fact_service_requests', conn, if_exists='replace', index=False)

    conn.commit()
    conn.close()

    print("\n" + "=" * 60)
    print(f"DATABASE SUCCESSFULLY CREATED: {DB_PATH}")
    print("=" * 60)
    print(f"- dim_suburb:           {len(dim_suburb):,} rows")
    print(f"- dim_category:         {len(dim_category):,} rows")
    print(f"- dim_date:             {len(dim_date):,} rows")
    print(f"- fact_service_requests:{len(fact_service_requests):,} rows")

if __name__ == "__main__":
    build_star_schema()