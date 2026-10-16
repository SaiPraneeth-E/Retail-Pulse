-- RetailPulse Database Security & Role Configuration
-- Phase 2: Least-privilege roles, connection guardrails, and audit tables.
-- Runs automatically on PostgreSQL container initialization.

-- 1. Create Airflow metadata database if it does not exist
SELECT 'CREATE DATABASE retailpulse_airflow'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'retailpulse_airflow')\gexec

-- 2. Create least-privilege application roles
DO $$
BEGIN
    -- Ingestion service role: write to raw and audit schemas only
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'retailpulse_ingest') THEN
        CREATE ROLE retailpulse_ingest WITH LOGIN PASSWORD 'changeme_in_env_file' CONNECTION LIMIT 10;
    END IF;

    -- Transformation role (dbt runner): read raw, write staging, marts, audit
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'retailpulse_transform') THEN
        CREATE ROLE retailpulse_transform WITH LOGIN PASSWORD 'changeme_in_env_file' CONNECTION LIMIT 15;
    END IF;

    -- BI Reader role (Power BI / analysts): read-only access to analytics schema ONLY
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'powerbi_reader') THEN
        CREATE ROLE powerbi_reader WITH LOGIN PASSWORD 'changeme_in_env_file' CONNECTION LIMIT 100;
    END IF;
END $$;

-- 3. Query timeouts and guardrails
ALTER ROLE powerbi_reader SET statement_timeout = '60s';
ALTER ROLE powerbi_reader SET idle_in_transaction_session_timeout = '30s';
ALTER ROLE retailpulse_transform SET statement_timeout = '300s';
ALTER ROLE retailpulse_ingest SET statement_timeout = '180s';

-- 4. Audit tables for pipeline tracking and data quality results
CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.pipeline_runs (
    run_id           TEXT PRIMARY KEY,
    dag_id           TEXT NOT NULL,
    execution_date   TEXT,
    status           TEXT NOT NULL, -- STARTED, SUCCEEDED, FAILED
    started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at      TIMESTAMPTZ,
    details          TEXT
);

CREATE TABLE IF NOT EXISTS audit.data_quality_results (
    quality_id       BIGSERIAL PRIMARY KEY,
    check_name       TEXT NOT NULL,
    table_name       TEXT NOT NULL,
    column_name      TEXT,
    check_type       TEXT NOT NULL,
    expected         TEXT,
    actual           TEXT,
    passed           BOOLEAN NOT NULL,
    checked_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    details          TEXT
);

COMMENT ON TABLE audit.pipeline_runs IS 'Tracks end-to-end Airflow DAG pipeline execution runs.';
COMMENT ON TABLE audit.data_quality_results IS 'Records automated data quality validation results.';
