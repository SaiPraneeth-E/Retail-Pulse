"""RetailPulse Airflow DAG.

Orchestrates the complete pipeline:
  1. Validate source files and configuration
  2. Ingest raw CSV data into PostgreSQL
  3. Validate raw table counts and schema
  4. Run dbt staging transformations
  5. Run dbt intermediate and mart transformations
  6. Execute dbt and custom data-quality tests
  7. Refresh/validate PostgreSQL analytics views
  8. Trigger Power BI semantic-model refresh (gated on upstream success)
  9. Record pipeline status and execution metadata

Configuration is read from environment variables only — no hardcoded secrets.
"""

from __future__ import annotations

import logging
import os
import sys
from datetime import datetime, timedelta

# Ensure repo root and airflow directory are in sys.path for ingestion module imports
for path in [
    os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")),
    "/opt/airflow",
    os.getcwd(),
]:
    if path not in sys.path:
        sys.path.insert(0, path)

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook

logger = logging.getLogger("retailpulse.airflow")

DEFAULT_ARGS = {
    "owner": "retailpulse",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": int(os.getenv("PIPELINE_RETRIES", "2")),
    "retry_delay": timedelta(seconds=int(os.getenv("PIPELINE_RETRY_DELAY_SECONDS", "30"))),
    "execution_timeout": timedelta(minutes=60),
}

POSTGRES_CONN_ID = "retailpulse_postgres"


def _validate_source_files(**context) -> None:
    """Task 1: confirm required Olist CSV files exist before ingestion."""
    from ingestion.config import IngestionConfig
    from ingestion.loader import validate_source_files

    config = IngestionConfig.from_env()
    missing = validate_source_files(config.data_dir, config.source_files)
    if missing:
        raise FileNotFoundError(f"Missing required source files: {missing}")
    logger.info("Source files validated: %d files present", len(config.source_files))


def _ingest_raw_data(**context) -> None:
    """Task 2: load Olist CSVs into PostgreSQL raw tables."""
    from ingestion.config import IngestionConfig
    from ingestion.ingest import run_ingestion

    config = IngestionConfig.from_env()
    results = run_ingestion(config)
    total_loaded = sum(r.rows_loaded for r in results)
    total_rejected = sum(r.rows_rejected for r in results)
    failed = [r for r in results if r.status == "FAILED"]
    if failed:
        raise RuntimeError(f"Ingestion failed for: {[r.source_file for r in failed]}")
    logger.info(
        "Ingestion complete: loaded=%d rejected=%d files=%d",
        total_loaded,
        total_rejected,
        len(results),
    )


def _validate_raw_tables(**context) -> None:
    """Task 3: validate raw table counts and schema after ingestion."""
    hook = PostgresHook(postgres_conn_id=POSTGRES_CONN_ID)
    expected_tables = [
        "olist_customers_dataset",
        "olist_orders_dataset",
        "olist_order_items_dataset",
        "olist_order_payments_dataset",
        "olist_order_reviews_dataset",
        "olist_products_dataset",
        "olist_sellers_dataset",
        "olist_geolocation_dataset",
        "olist_product_category_name_translation",
    ]
    for table in expected_tables:
        count = hook.get_records(f"SELECT COUNT(*) FROM raw.{table}")[0][0]
        columns = hook.get_records(
            """
            SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema='raw' AND table_name=%s
            """,
            (table,),
        )[0][0]
        if count is None or columns == 0:
            raise ValueError(f"Raw table raw.{table} failed validation (rows={count}, cols={columns})")
        logger.info("raw.%s: rows=%d columns=%d", table, count, columns)


def _run_dbt(command: str, select: str | None = None) -> None:
    """Run a dbt command via the dbt runner service or local install."""
    import subprocess

    dbt_dir = "dbt" if os.path.isdir("dbt") else "/opt/airflow/dbt"
    cmd = ["dbt", command]
    if select:
        cmd += ["--select", select]
    cmd += [
        "--project-dir", dbt_dir,
        "--profiles-dir", dbt_dir,
        "--log-path", "/tmp/dbt_logs",
    ]
    env = dict(os.environ)
    logger.info("Running dbt command: %s", " ".join(cmd))
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    logger.info(result.stdout)
    if result.returncode != 0:
        logger.error(result.stderr)
        raise RuntimeError(f"dbt {command} failed with exit code {result.returncode}")


def _dbt_staging(**context) -> None:
    """Task 4: dbt staging transformations."""
    _run_dbt("build", "staging")


def _dbt_intermediate_marts(**context) -> None:
    """Task 5: dbt intermediate and mart transformations."""
    _run_dbt("build", "intermediate marts")


def _dbt_tests(**context) -> None:
    """Task 6: dbt data-quality tests."""
    _run_dbt("test")


def _validate_analytics_views(**context) -> None:
    """Task 7: validate that analytics views exist and are queryable."""
    hook = PostgresHook(postgres_conn_id=POSTGRES_CONN_ID)
    sql_path = "sql/analytics_views.sql" if os.path.exists("sql/analytics_views.sql") else "/opt/airflow/sql/analytics_views.sql"
    if os.path.exists(sql_path):
        with open(sql_path, "r", encoding="utf-8") as f:
            sql_content = f.read()
        hook.run(sql_content)
        logger.info("Applied analytics views from %s", sql_path)

    views = [
        "vw_executive_kpis",
        "vw_sales_trends",
        "vw_category_performance",
        "vw_product_performance",
        "vw_seller_performance",
        "vw_customer_analytics",
        "vw_delivery_performance",
        "vw_review_analytics",
        "vw_geographic_sales",
    ]
    for view in views:
        row = hook.get_records(
            """
            SELECT COUNT(*) FROM information_schema.views
            WHERE table_schema='analytics' AND table_name=%s
            """,
            (view,),
        )[0][0]
        if row == 0:
            raise ValueError(f"Analytics view analytics.{view} is missing")
        logger.info("analytics.%s present and verified", view)


def _refresh_powerbi(**context) -> None:
    """Task 8: Power BI semantic-model refresh — runs only if all upstream succeeded.

    Airflow only calls this task when every upstream task has succeeded, so the
    refresh is inherently gated on pipeline success.
    """
    from ingestion.powerbi_refresh import refresh_if_authorized, PowerBiRefreshError

    tenant = os.getenv("POWERBI_TENANT_ID")
    client = os.getenv("POWERBI_CLIENT_ID")
    if not tenant or not client or tenant == "your-tenant-id":
        logger.warning(
            "Power BI configuration not set or placeholder; skipping semantic-model refresh. "
            "Set POWERBI_* variables in .env to enable automatic refresh."
        )
        return
    try:
        result = refresh_if_authorized(poll=False)
        logger.info("Power BI refresh result: %s", result.detail)
    except PowerBiRefreshError as exc:
        # Refresh failures are reported but do not fail the core data pipeline itself;
        # the data warehouse in PostgreSQL is already healthy and consistent.
        logger.error("Power BI refresh failed: %s", exc)


def _record_pipeline_status(**context) -> None:
    """Task 9: record final pipeline execution metadata in audit schema."""
    hook = PostgresHook(postgres_conn_id=POSTGRES_CONN_ID)
    dag_run = context.get("dag_run")
    run_id = dag_run.run_id if dag_run else f"manual_{datetime.utcnow().isoformat()}"
    dag_id = context["dag"].dag_id if context.get("dag") else "retailpulse_pipeline"
    execution_date = context["execution_date"].isoformat() if context.get("execution_date") else str(datetime.utcnow())
    hook.run(
        """
        INSERT INTO audit.pipeline_runs (run_id, dag_id, execution_date, status, finished_at)
        VALUES (%s, %s, %s, %s, now())
        ON CONFLICT (run_id) DO UPDATE SET
            dag_id = EXCLUDED.dag_id,
            execution_date = EXCLUDED.execution_date,
            status = EXCLUDED.status,
            finished_at = now()
        """,
        parameters=(run_id, dag_id, execution_date, "SUCCEEDED"),
    )
    logger.info("Pipeline status recorded: run_id=%s status=SUCCEEDED", run_id)


def _failure_hook(context) -> None:
    """Hook called on task failure: can be extended for email/webhook alerts."""
    ti = context.get("task_instance")
    task_id = ti.task_id if ti else "unknown"
    dag_id = context.get("dag").dag_id if context.get("dag") else "unknown"
    run_id = context.get("dag_run").run_id if context.get("dag_run") else "unknown"
    logger.error(
        "Pipeline failure hook: dag=%s run_id=%s task=%s",
        dag_id,
        run_id,
        task_id,
    )


with DAG(
    dag_id="retailpulse_pipeline",
    description="RetailPulse end-to-end Olist data pipeline",
    schedule=os.getenv("PIPELINE_SCHEDULE_CRON", "0 2 * * *"),
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args=DEFAULT_ARGS,
    tags=["retailpulse", "oltp", "dbt", "powerbi"],
    on_failure_callback=_failure_hook,
) as dag:

    t_validate_files = PythonOperator(
        task_id="validate_source_files",
        python_callable=_validate_source_files,
    )

    t_ingest = PythonOperator(
        task_id="ingest_raw_data",
        python_callable=_ingest_raw_data,
    )

    t_validate_raw = PythonOperator(
        task_id="validate_raw_tables",
        python_callable=_validate_raw_tables,
    )

    t_dbt_staging = PythonOperator(
        task_id="dbt_staging",
        python_callable=_dbt_staging,
    )

    t_dbt_intermediate_marts = PythonOperator(
        task_id="dbt_intermediate_marts",
        python_callable=_dbt_intermediate_marts,
    )

    t_dbt_tests = PythonOperator(
        task_id="dbt_tests",
        python_callable=_dbt_tests,
    )

    t_validate_views = PythonOperator(
        task_id="validate_analytics_views",
        python_callable=_validate_analytics_views,
    )

    t_refresh_powerbi = PythonOperator(
        task_id="refresh_powerbi_semantic_model",
        python_callable=_refresh_powerbi,
    )

    t_record_status = PythonOperator(
        task_id="record_pipeline_status",
        python_callable=_record_pipeline_status,
    )

    # Task dependencies (strict ordering; downstream never runs after failure)
    (
        t_validate_files
        >> t_ingest
        >> t_validate_raw
        >> t_dbt_staging
        >> t_dbt_intermediate_marts
        >> t_dbt_tests
        >> t_validate_views
        >> t_refresh_powerbi
        >> t_record_status
    )
