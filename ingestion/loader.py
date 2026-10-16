"""CSV validation and bulk loading into PostgreSQL raw tables."""

from __future__ import annotations

import csv
import os
from dataclasses import dataclass
from typing import Iterator, List, Optional

import psycopg2
from psycopg2.extras import execute_values

from .logger import get_logger
from .metadata import FileRunResult, compute_file_checksum

logger = get_logger("retailpulse.ingestion.loader")

# Mapping of source file -> raw table name
FILE_TO_TABLE = {
    "olist_customers_dataset.csv": "raw.olist_customers_dataset",
    "olist_orders_dataset.csv": "raw.olist_orders_dataset",
    "olist_order_items_dataset.csv": "raw.olist_order_items_dataset",
    "olist_order_payments_dataset.csv": "raw.olist_order_payments_dataset",
    "olist_order_reviews_dataset.csv": "raw.olist_order_reviews_dataset",
    "olist_products_dataset.csv": "raw.olist_products_dataset",
    "olist_sellers_dataset.csv": "raw.olist_sellers_dataset",
    "olist_geolocation_dataset.csv": "raw.olist_geolocation_dataset",
    "olist_product_category_name_translation.csv": "raw.olist_product_category_name_translation",
}

REQUIRED_FILES = list(FILE_TO_TABLE.keys())

# Column aliases for variations between Kaggle dataset headers and relational standards
COLUMN_ALIASES = {
    "product_name_length": ["product_name_length", "product_name_lenght"],
    "product_description_length": ["product_description_length", "product_description_lenght"],
}


@dataclass
class LoadSummary:
    source_file: str
    target_table: str
    rows_read: int
    rows_loaded: int
    rows_rejected: int
    rejected_reasons: List[str]


def validate_source_files(data_dir: str, source_files: List[str]) -> List[str]:
    """Validate that required source files exist. Returns list of missing files."""
    missing: List[str] = []
    for filename in source_files:
        path = os.path.join(data_dir, filename)
        if not os.path.isfile(path):
            missing.append(filename)
    return missing


def read_csv_rows(path: str) -> Iterator[dict]:
    """Yield rows from a CSV file, tolerating malformed rows by skipping them."""
    with open(path, newline="", encoding="utf-8-sig") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            yield row


def clean_value(value: Optional[str]):
    """Convert empty strings to None; otherwise return the string as-is."""
    if value is None:
        return None
    value = value.strip()
    if value == "":
        return None
    return value


def _get_row_value(row: dict, col: str):
    """Retrieve column value from row checking configured aliases."""
    if col in row:
        return clean_value(row.get(col))
    aliases = COLUMN_ALIASES.get(col, [])
    for alias in aliases:
        if alias in row:
            return clean_value(row.get(alias))
    return None


def bulk_load(
    conn,
    source_file: str,
    data_dir: str,
    batch_size: int = 10_000,
) -> LoadSummary:
    """Load one CSV file into its raw table using batched inserts.

    The load is repeatable: the target raw table is truncated before load so
    reruns produce identical results (no duplicate accumulation).
    Uses SAVEPOINTs for robust batch error isolation.
    """
    table = FILE_TO_TABLE[source_file]
    path = os.path.join(data_dir, source_file)
    checksum = compute_file_checksum(path)

    cur = conn.cursor()
    try:
        cur.execute(f"TRUNCATE TABLE {table} RESTART IDENTITY CASCADE;")

        rows_read = 0
        rows_loaded = 0
        rows_rejected = 0
        rejected_reasons: List[str] = []
        batch: List[tuple] = []

        # Determine columns dynamically from table schema
        schema_name, table_name = table.split(".", 1)
        cur.execute(
            """
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = %s
              AND table_name = %s
              AND (column_default IS NULL OR column_default NOT LIKE %s)
            ORDER BY ordinal_position
            """,
            (schema_name, table_name, "nextval(%)"),
        )
        all_db_cols = [row[0] for row in cur.fetchall()]

        with open(path, newline="", encoding="utf-8-sig") as fh:
            reader = csv.DictReader(fh)
            csv_columns = set(reader.fieldnames or [])

            # Keep only DB columns that match either a CSV column or an alias
            db_columns = []
            for col in all_db_cols:
                if col in csv_columns:
                    db_columns.append(col)
                elif col in COLUMN_ALIASES and any(a in csv_columns for a in COLUMN_ALIASES[col]):
                    db_columns.append(col)

            cols_sql = ", ".join(db_columns)
            insert_query = f"INSERT INTO {table} ({cols_sql}) VALUES %s"

            for row in reader:
                rows_read += 1
                values = [_get_row_value(row, col) for col in db_columns]
                batch.append(tuple(values))

                if len(batch) >= batch_size:
                    try:
                        cur.execute("SAVEPOINT batch_savepoint;")
                        execute_values(cur, insert_query, batch, page_size=batch_size)
                        cur.execute("RELEASE SAVEPOINT batch_savepoint;")
                        rows_loaded += len(batch)
                    except Exception as exc:  # noqa: BLE001
                        cur.execute("ROLLBACK TO SAVEPOINT batch_savepoint;")
                        rows_rejected += len(batch)
                        rejected_reasons.append(str(exc)[:200])
                    batch = []

            # Flush final batch
            if batch:
                try:
                    cur.execute("SAVEPOINT batch_savepoint;")
                    execute_values(cur, insert_query, batch, page_size=batch_size)
                    cur.execute("RELEASE SAVEPOINT batch_savepoint;")
                    rows_loaded += len(batch)
                except Exception as exc:  # noqa: BLE001
                    cur.execute("ROLLBACK TO SAVEPOINT batch_savepoint;")
                    rows_rejected += len(batch)
                    rejected_reasons.append(str(exc)[:200])

        conn.commit()
        return LoadSummary(
            source_file=source_file,
            target_table=table,
            rows_read=rows_read,
            rows_loaded=rows_loaded,
            rows_rejected=rows_rejected,
            rejected_reasons=rejected_reasons,
        )
    finally:
        cur.close()
