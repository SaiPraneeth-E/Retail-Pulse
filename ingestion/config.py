"""Ingestion configuration loaded from environment variables."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import List


@dataclass(frozen=True)
class IngestionConfig:
    """Runtime configuration for the Olist ingestion framework."""

    data_dir: str
    source_files: List[str]
    db_host: str
    db_port: int
    db_name: str
    db_user: str
    db_password: str
    batch_size: int = 10_000
    log_level: str = "INFO"

    @classmethod
    def from_env(cls) -> "IngestionConfig":
        data_dir = os.getenv("OLIST_DATA_DIR", "./data/olist")

        files_env = os.getenv("OLIST_SOURCE_FILES", "")
        if files_env:
            source_files = [f.strip() for f in files_env.split(",") if f.strip()]
        else:
            source_files = [
                "olist_customers_dataset.csv",
                "olist_orders_dataset.csv",
                "olist_order_items_dataset.csv",
                "olist_order_payments_dataset.csv",
                "olist_order_reviews_dataset.csv",
                "olist_products_dataset.csv",
                "olist_sellers_dataset.csv",
                "olist_geolocation_dataset.csv",
                "olist_product_category_name_translation.csv",
            ]

        return cls(
            data_dir=data_dir,
            source_files=source_files,
            db_host=os.getenv("PGHOST", "localhost"),
            db_port=int(os.getenv("PGPORT", "5432")),
            db_name=os.getenv("POSTGRES_DB", "retailpulse"),
            db_user=os.getenv("POSTGRES_USER", "retailpulse"),
            db_password=os.getenv("POSTGRES_PASSWORD", ""),
            batch_size=int(os.getenv("INGEST_BATCH_SIZE", "10000")),
            log_level=os.getenv("INGEST_LOG_LEVEL", "INFO"),
        )

    def file_path(self, filename: str) -> str:
        return os.path.join(self.data_dir, filename)
