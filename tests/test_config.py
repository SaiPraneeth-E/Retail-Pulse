"""Unit tests for ingestion configuration and validation."""

from __future__ import annotations

import os
from unittest.mock import patch

import pytest

from ingestion.config import IngestionConfig


def test_config_from_env_defaults(monkeypatch):
    monkeypatch.setenv("OLIST_DATA_DIR", "./data/olist")
    monkeypatch.setenv("PGHOST", "localhost")
    monkeypatch.setenv("PGPORT", "5432")
    monkeypatch.setenv("POSTGRES_DB", "retailpulse")
    monkeypatch.setenv("POSTGRES_USER", "retailpulse")
    monkeypatch.setenv("POSTGRES_PASSWORD", "pw")
    cfg = IngestionConfig.from_env()
    assert cfg.data_dir == "./data/olist"
    assert cfg.db_host == "localhost"
    assert cfg.db_port == 5432
    assert cfg.db_name == "retailpulse"
    assert cfg.db_user == "retailpulse"
    assert cfg.db_password == "pw"
    assert cfg.batch_size == 10000
    assert len(cfg.source_files) == 9


def test_config_custom_source_files(monkeypatch):
    monkeypatch.setenv("OLIST_SOURCE_FILES", "olist_orders_dataset.csv,olist_customers_dataset.csv")
    cfg = IngestionConfig.from_env()
    assert cfg.source_files == ["olist_orders_dataset.csv", "olist_customers_dataset.csv"]


def test_config_file_path():
    import os
    cfg = IngestionConfig(
        data_dir="./data/olist",
        source_files=[],
        db_host="localhost",
        db_port=5432,
        db_name="db",
        db_user="u",
        db_password="p",
    )
    assert cfg.file_path("olist_orders_dataset.csv") == os.path.join(
        "./data/olist", "olist_orders_dataset.csv"
    )


def test_validate_source_files_missing(tmp_path, monkeypatch):
    from ingestion.loader import validate_source_files
    monkeypatch.chdir(tmp_path)
    missing = validate_source_files("./data/olist", ["a.csv", "b.csv"])
    assert "a.csv" in missing
    assert "b.csv" in missing


def test_validate_source_files_present(tmp_path, monkeypatch):
    from ingestion.loader import validate_source_files
    data_dir = tmp_path / "data" / "olist"
    data_dir.mkdir(parents=True)
    (data_dir / "olist_orders_dataset.csv").write_text("order_id\n1\n")
    (data_dir / "olist_customers_dataset.csv").write_text("customer_id\nc1\n")
    missing = validate_source_files(str(data_dir), ["olist_orders_dataset.csv", "olist_customers_dataset.csv"])
    assert missing == []


def test_config_env_missing_password_ok(monkeypatch):
    # Password optional at config load time; connection fails later, not here.
    monkeypatch.delenv("POSTGRES_PASSWORD", raising=False)
    cfg = IngestionConfig.from_env()
    assert cfg.db_password == ""
