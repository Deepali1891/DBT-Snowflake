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

### 2. Create and activate a virtual environment (recommended)

Create an isolated Python environment to keep dependencies local to this project.

POSIX / macOS:

```bash
python -m venv .venv
source .venv/bin/activate
```

Windows (PowerShell):

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

Windows (Command Prompt):

```cmd
python -m venv .venv
.venv\Scripts\activate.bat
```

After activating the virtual environment, install dbt and the Snowflake adapter in the next step.

### 3. Install dbt and the Snowflake adapter

```bash
pip install dbt-snowflake
```

### 4. Set your Snowflake credentials

Copy the example environment file and fill in your values:

```bash
cp .env.example .env
# edit .env with your credentials
```

Then export the variables (or use a tool like [direnv](https://direnv.net/)):

```bash
export $(grep -v '^#' .env | xargs)
```

### 5. Configure the dbt profile

Copy `profiles.yml` to your dbt home directory:

```bash
cp profiles.yml ~/.dbt/profiles.yml
```

The profile reads credentials from environment variables so no secrets are stored in the file.

### 6. Install dbt packages

```bash
dbt deps
```

### 7. Test the Snowflake connection

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

## Silver Layer – Staging Models

**Why it exists:** The Olist dataset arrives from S3 as headerless CSV files. Snowflake loads these into bronze tables with positional column names (`"c1"`, `"c2"`, ..., `"cN"`). The silver layer's primary job is to give every column a meaningful name, enforce correct data types, and remove unusable rows — so all downstream models can rely on clean, trustworthy data without re-implementing the same defensive logic.

Each `stg_*` model is a direct, 1-to-1 transformation of a single source table. No inter-model joins occur at this layer; silver is intentionally a clean copy of bronze, not a derived view.

| Model | Source Table | Key Intent |
|---|---|---|
| `stg_customers` | `raw_customers` | Only bronze table with named columns — cast zip code to VARCHAR |
| `stg_orders` | `raw_orders` | Alias positional columns, dedup, cast all timestamps |
| `stg_order_items` | `raw_order_items` | Alias positional columns, cast price and freight to FLOAT |
| `stg_products` | `raw_products` | Alias positional columns, translate category names to English |
| `stg_payments` | `raw_order_payments` | Alias positional columns, normalize `payment_type` |
| `stg_order_reviews` | `raw_order_reviews` | Alias positional columns, validate `review_score` in range [1, 5] |
| `stg_sellers` | `raw_sellers` | Alias positional columns, normalize city/state |
| `stg_geolocation` | `raw_geolocation` | Alias positional columns, collapse to **one row per zip** by averaging lat/lng |

**Key design decisions:**

- **Positional column aliasing** — Every source CTE uses explicit `"c1" as column_name` aliases. `SELECT *` from bronze would return unlabelled columns and break all downstream logic.
- **Geolocation dedup** — `raw_geolocation` has many rows per zip code (varying coordinates). Silver reduces this to one representative row per zip to prevent join fan-out in gold.
- **City normalization** — Applied in `stg_customers`, `stg_sellers`, and `stg_geolocation` using a hand-curated map for top cities with correct Portuguese diacritics (e.g., `São Paulo`, `Brasília`), and `INITCAP` as a fallback for all others.
- **Row exclusions** — Null primary keys, `price <= 0`, `review_score` outside [1, 5], and future-dated purchase timestamps are filtered out.
- **Deduplication** — All models remove duplicate rows using `ROW_NUMBER()` on their natural primary key before exposing data to gold.

---

## Gold Layer – Foundation Tables & Product Marts

**Why it exists:** Silver models are clean representations of individual source tables. Gold is where sources are joined, metrics are computed, and results are shaped into answers to specific business questions.

The gold layer has two tiers:

**Foundation tables** (`fct_*`, `dim_*`) are general-purpose building blocks. They join silver models once, compute core metrics, and serve as the shared input for all marts — avoiding duplicated join logic across downstream models.

**Product marts** (`mart_product_*`) each answer one focused question about product performance. They are pre-aggregated, self-contained, and intended to be queried directly by BI tools or analysts without further transformation.

### Foundation Tables

| Model | Grain | Purpose |
|---|---|---|
| `fct_order_items` | One row per order line item | Core transactional fact: price, freight, seller, and an `is_single_item_order` flag |
| `fct_orders` | One row per order | Aggregated order: total payment, delivery days, on-time flag, avg satisfaction score |
| `dim_products` | One row per product | Product catalog with avg/min/max price and a `price_tier` (Budget / Mid-range / Premium) derived via `NTILE(3)` within each category |

### Product Marts

| Model | Grain | Question answered |
|---|---|---|
| `mart_product_lifecycle` | One row per product | When did this product enter the market? How is volume distributed across age buckets (months 1–3, 4–6, 7–12, 13+)? What is its lifecycle classification? |
| `mart_product_sales_cohort` | One row per product × calendar month | What does revenue look like month by month, normalised to *months since market entry* for fair cross-product comparison? |
| `mart_product_engagement` | One row per product | How many buyers were new to the platform? How many returned for a repeat purchase? How many sellers carry this product? |
| `mart_product_experience` | One row per product | What is the clean satisfaction signal for this product, and is it improving or declining over time? |
| `mart_product_campaign_score` | One row per product | Which products deserve marketing investment right now, and why? |

**Key design decisions:**

- **`market_entry_date` vs. a catalog launch date** — The dataset has no product launch date. `market_entry_date` is defined as the earliest *delivered* order date for each product. This is a data-inferred proxy, not an authoritative record; the column name was chosen to make that limitation explicit.
- **`mart_product_experience` scoped to single-item orders only** — Customer reviews are attached to orders, not to individual products. In multi-item orders (~10% of all orders) it is impossible to know which product a review reflects. This mart filters to single-item orders and surfaces a `satisfaction_scope = 'single_item_orders_only'` column so consumers understand the constraint.
- **`price_tier` computed within category** — Tiers are derived via `NTILE(3)` partitioned by `product_category`, not globally. "Premium" means the top third of *that category's* price range, giving the label contextual meaning instead of an absolute price cutoff.
- **Campaign score weighting** — `mart_product_campaign_score` combines four signals into a 0–100 composite score:
  - Lifecycle stage (30%) — rewards products in early, high-growth periods
  - Recent sales trend (25%) — rewards rising momentum
  - Engagement (25%) — rewards high repeat-purchase rates
  - Satisfaction (20%) — penalises poor or declining reviews

  Output is a `campaign_recommendation` label: **High Priority**, **Reactivate**, **Monitor**, or **Retire**.

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
│   │   ├── stg_customers.sql         # Cleaned customer records
│   │   ├── stg_orders.sql            # Cleaned order records
│   │   ├── stg_order_items.sql       # Cleaned order line item records
│   │   ├── stg_products.sql          # Cleaned product records (English categories)
│   │   ├── stg_payments.sql          # Cleaned payment records
│   │   ├── stg_order_reviews.sql     # Cleaned review records
│   │   ├── stg_sellers.sql           # Cleaned seller records
│   │   ├── stg_geolocation.sql       # One row per zip code (lat/lng averaged)
│   │   └── schema.yml                # Column docs & tests for silver models
│   └── gold/
│       ├── fct_order_items.sql            # Order line item fact table
│       ├── fct_orders.sql                 # Order-level fact table
│       ├── dim_products.sql               # Product catalog with price tiers
│       ├── mart_product_lifecycle.sql     # Lifecycle classification and age buckets
│       ├── mart_product_sales_cohort.sql  # Month-by-month revenue per product
│       ├── mart_product_engagement.sql    # Repeat-buyer and new-buyer metrics
│       ├── mart_product_experience.sql    # Satisfaction scores (single-item orders)
│       ├── mart_product_campaign_score.sql  # Composite campaign potential score
│       └── schema.yml                     # Column docs & tests for gold models
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
| `dbt docs generate` | Generate documentation site |
| `dbt docs serve` | Serve documentation locally at http://localhost:8080 |
| `dbt compile` | Compile SQL without executing |
| `dbt source freshness` | Check source data freshness |
