# DBT-Snowflake

A production-ready **dbt** project for building a medallion-architecture data pipeline on **Snowflake**.  
Raw data is loaded from **AWS S3** into the **bronze** layer and then progressively refined through **silver** (staging/cleaning) and **gold** (business-ready) models.

---

## Architecture

```
AWS S3  ──COPY INTO──►  Bronze (raw tables)
                              │
                    dbt silver models (stg_*)
                              │
                    dbt gold models (dim_*, fct_*, mart_*)
```

| Layer  | Schema   | Materialisation | Description |
|--------|----------|-----------------|-------------|
| Bronze | `bronze` | view            | Raw tables loaded from S3 — source of truth |
| Silver | `silver` | table           | Cleaned, typed, and normalised staging models |
| Gold   | `gold`   | table           | Dimension tables, fact tables, and analytics marts |

---

## Prerequisites

| Tool | Minimum Version |
|------|----------------|
| Python | 3.8+ |
| dbt-core | 1.5+ |
| dbt-snowflake | 1.5+ |
| Snowflake account | any |

---

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/Deepali1891/DBT-Snowflake.git
cd DBT-Snowflake
```

### 2. Install dbt and the Snowflake adapter

```bash
pip install dbt-snowflake
```

### 3. Set your Snowflake credentials

Copy the example environment file and fill in your values:

```bash
cp .env.example .env
# edit .env with your credentials
```

Then export the variables (or use a tool like [direnv](https://direnv.net/)):

```bash
export $(grep -v '^#' .env | xargs)
```

### 4. Configure the dbt profile

Copy `profiles.yml` to your dbt home directory:

```bash
cp profiles.yml ~/.dbt/profiles.yml
```

The profile reads credentials from environment variables so no secrets are stored in the file.

### 5. Install dbt packages

```bash
dbt deps
```

### 6. Test the Snowflake connection

```bash
dbt debug
```

---

## Bronze Layer – Loading Data from S3

Before running the dbt models you must load the raw tables into Snowflake.  
Below is a minimal Snowflake setup script. Run it once in a Snowflake worksheet:

```sql
-- Create objects
CREATE DATABASE IF NOT EXISTS ANALYTICS;
CREATE SCHEMA   IF NOT EXISTS ANALYTICS.BRONZE;
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
    WAREHOUSE_SIZE = 'X-SMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;

-- Create an S3 external stage (replace with your bucket details)
CREATE STAGE IF NOT EXISTS ANALYTICS.BRONZE.s3_stage
    URL = 's3://your-bucket/data/'
    CREDENTIALS = (AWS_KEY_ID = '<key>' AWS_SECRET_KEY = '<secret>');

-- Create raw tables
CREATE TABLE IF NOT EXISTS ANALYTICS.BRONZE.RAW_ORDERS (
    order_id         VARCHAR,
    customer_id      VARCHAR,
    product_id       VARCHAR,
    order_date       DATE,
    quantity         INTEGER,
    unit_price_cents INTEGER,
    status           VARCHAR,
    created_at       TIMESTAMP_NTZ,
    updated_at       TIMESTAMP_NTZ
);

CREATE TABLE IF NOT EXISTS ANALYTICS.BRONZE.RAW_CUSTOMERS (
    customer_id  VARCHAR,
    first_name   VARCHAR,
    last_name    VARCHAR,
    email        VARCHAR,
    phone        VARCHAR,
    country      VARCHAR,
    city         VARCHAR,
    created_at   TIMESTAMP_NTZ,
    updated_at   TIMESTAMP_NTZ
);

CREATE TABLE IF NOT EXISTS ANALYTICS.BRONZE.RAW_PRODUCTS (
    product_id       VARCHAR,
    product_name     VARCHAR,
    category         VARCHAR,
    subcategory      VARCHAR,
    unit_price_cents INTEGER,
    is_active        BOOLEAN,
    created_at       TIMESTAMP_NTZ,
    updated_at       TIMESTAMP_NTZ
);

-- Load data from S3
COPY INTO ANALYTICS.BRONZE.RAW_ORDERS    FROM @s3_stage/orders/    FILE_FORMAT = (TYPE = CSV SKIP_HEADER = 1);
COPY INTO ANALYTICS.BRONZE.RAW_CUSTOMERS FROM @s3_stage/customers/ FILE_FORMAT = (TYPE = CSV SKIP_HEADER = 1);
COPY INTO ANALYTICS.BRONZE.RAW_PRODUCTS  FROM @s3_stage/products/  FILE_FORMAT = (TYPE = CSV SKIP_HEADER = 1);
```

---

## Running dbt Models

### Run all models (silver + gold)

```bash
dbt run
```

### Run a specific layer

```bash
dbt run --select silver
dbt run --select gold
```

### Run a single model

```bash
dbt run --select stg_orders
dbt run --select fct_orders
```

---

## Testing

### Run all tests

```bash
dbt test
```

### Run tests for a specific layer

```bash
dbt test --select silver
dbt test --select gold
```

### Run tests for a single model

```bash
dbt test --select stg_orders
```

Tests cover:

- **not_null** — no nulls in key columns
- **unique** — primary keys are unique
- **accepted_values** — status columns contain only valid values
- **relationships** — foreign-key integrity between models
- **positive_value** — custom generic test ensuring quantities/prices are > 0

---

## Snapshots (Type-2 SCD)

Capture historical changes to the customers table:

```bash
dbt snapshot
```

The snapshot is stored in the `snapshots` schema and tracks changes using the `updated_at` timestamp strategy.

---

## Project Structure

```
DBT-Snowflake/
├── dbt_project.yml              # Project configuration
├── packages.yml                 # dbt package dependencies
├── profiles.yml                 # Snowflake connection profile template
├── .env.example                 # Environment variable template
├── analyses/
│   └── monthly_revenue_summary.sql   # Ad-hoc analysis query
├── macros/
│   ├── cents_to_dollars.sql     # Convert integer cents to decimal dollars
│   ├── clean_string.sql         # Trim and title-case string columns
│   ├── generate_schema_name.sql # Override default schema naming
│   ├── generate_surrogate_key.sql    # Wrapper around dbt_utils surrogate key
│   └── safe_divide.sql          # Division that returns null instead of error
├── models/
│   ├── bronze/
│   │   └── sources.yml          # Source definitions for raw S3-loaded tables
│   ├── silver/
│   │   ├── stg_customers.sql    # Cleaned customer records
│   │   ├── stg_orders.sql       # Cleaned order records
│   │   ├── stg_products.sql     # Cleaned product records
│   │   └── schema.yml           # Column docs & tests for silver models
│   └── gold/
│       ├── dim_customers.sql    # Customer dimension with order metrics
│       ├── dim_products.sql     # Product dimension with sales metrics
│       ├── fct_orders.sql       # Central orders fact table
│       ├── mart_customer_orders.sql  # Customer-level order analytics mart
│       └── schema.yml           # Column docs & tests for gold models
├── snapshots/
│   └── customers_snapshot.sql  # Type-2 SCD snapshot for customers
└── tests/
    └── generic/
        └── positive_value.sql   # Custom generic test: value must be > 0
```

---

## Macros Reference

| Macro | Signature | Description |
|-------|-----------|-------------|
| `cents_to_dollars` | `(column_name, scale=2)` | Divides an integer cents column by 100 and rounds to `scale` decimal places |
| `clean_string` | `(column_name)` | Applies `INITCAP(TRIM(...))` to normalise a string column |
| `safe_divide` | `(numerator, denominator)` | Returns `NULL` instead of an error when the denominator is 0 or NULL |
| `generate_surrogate_key` | `(column_list)` | Thin wrapper around `dbt_utils.generate_surrogate_key` |
| `generate_schema_name` | `(custom_schema_name, node)` | Overrides dbt's default schema-naming behaviour to use the custom schema name directly |

---

## Useful dbt Commands

| Command | Description |
|---------|-------------|
| `dbt debug` | Verify connection and project configuration |
| `dbt deps` | Install packages from `packages.yml` |
| `dbt run` | Build all models |
| `dbt test` | Run all schema and custom tests |
| `dbt snapshot` | Run snapshots |
| `dbt docs generate` | Generate documentation site |
| `dbt docs serve` | Serve documentation locally at http://localhost:8080 |
| `dbt compile` | Compile SQL without executing |
| `dbt source freshness` | Check source data freshness |
