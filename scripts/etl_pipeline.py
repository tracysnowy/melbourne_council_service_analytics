import os
import pandas as pd

# Define the files 
RAW_FILE_PATH = "data/raw/customer-service-requests-with-resolution-time.csv"
PROCESSED_DIR = "data/processed"
PROCESSED_FILE_PATH = os.path.join(PROCESSED_DIR, "customer_requests_cleaned.csv")

# SLA target days for each category
SLA_TARGETS = {
    'Parking': 3,
    'Waste, Street Cleaning and Litter': 5,
    'Graffiti': 7,
    'Parks and Trees': 10,
    'Roads and Traffic': 14,
    'Asset maintenance': 21
}

def run_etl():
    print("=" * 60)
    print("STARTING ETL PIPELINE")
    print("=" * 60)

    # Load the raw dataset
    print("\nLoading raw dataset...")
    df = pd.read_csv(RAW_FILE_PATH)
    print (f"Loaded dataset with {df.shape[0]:,} rows and {df.shape[1]} columns successfully.")

    # Standardize column names (lowercase snake_case)
    print("\nStandardizing column names...")
    df.columns = df.columns.str.strip().str.lower().str.replace(' ', '_')

    #Parse date columns
    print("\nParsing datetime fields...")
    df['date_received'] = pd.to_datetime(df['date_received'], errors='coerce')
    df['date_completed'] = pd.to_datetime(df['date_completed'], errors='coerce')

    #Extract date parts for analytical dimensions
    df['received_year'] = df['date_received'].dt.year
    df['received_month'] = df['date_received'].dt.month
    df['received_month_name'] = df['date_received'].dt.strftime('%b')
    df['received_day_name'] = df['date_received'].dt.strftime('%a')

    #Handle missing values
    print("\nHandling missing values...")
    df['suburb'] = df['suburb'].fillna('Unspecified').str.strip()
    df['request_status'] = df['request_status'].str.strip().str.upper()
    df['category'] = df['category'].str.strip()
    df['service_desc'] = df['service_desc'].str.strip()

    #Apply SLA logic & performance metrics
    print("\nComputing SLA performance metrics...")
    df['sla_target_days'] = df['category'].map(SLA_TARGETS).fillna(14).astype(int)  # Default SLA target is 14 days for unspecified categories

    #Classify SLA status: Breached, Met, or Pending
    def assign_sla_status(row):
        if pd.isna(row['date_completed']):
            return 'Pending'
        elif row['days_to_complete'] > row['sla_target_days']:
            return 'Breached'
        else:
            return 'Met'
        
    df['sla_status'] = df.apply(assign_sla_status, axis=1)
    df['is_sla_breached'] = (df['sla_status'] == 'Breached').astype(int)

    #Ensure processed directory exists
    os.makedirs(PROCESSED_DIR, exist_ok=True)

    #Save cleaned dataset
    df.to_csv(PROCESSED_FILE_PATH, index=False)
    print("\n" + "=" * 60)
    print(f"ETL Pipeline completed successfully. Processed data saved to {PROCESSED_FILE_PATH}")
    print("=" * 60)

    #Validation summary
    print("\nSLA STATUS BREAKDOWN:")
    print(df['sla_status'].value_counts(dropna=False))
    completed_df = df[df['sla_status'] != 'Pending']
    breach_rate = (completed_df['sla_status'] == 'Breached').mean() * 100
    print(f"\nOverall SLA Breach Rate (Completed Only): {breach_rate:.2f}%")

if __name__ == "__main__":
    run_etl()