-- RetailPulse PostgreSQL warehouse initialization
-- Phase 2: logical schemas
-- Run against the retailpulse database (created via POSTGRES_DB env var).

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS audit;

COMMENT ON SCHEMA raw IS 'Source data loaded with minimal transformation from Olist CSV files.';
COMMENT ON SCHEMA staging IS 'Standardized source models (dbt staging layer source).';
COMMENT ON SCHEMA analytics IS 'Business-ready facts, dimensions, and reporting views.';
COMMENT ON SCHEMA audit IS 'Pipeline execution metadata and data-quality results.';
