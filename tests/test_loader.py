"""Unit tests for ingestion loading, cleaning, and validation functions."""

from __future__ import annotations

import os
import tempfile
import pytest

from ingestion.loader import (
    clean_value,
    _get_row_value,
    validate_source_files,
    read_csv_rows,
    REQUIRED_FILES,
    FILE_TO_TABLE,
    COLUMN_ALIASES,
)
from ingestion.metadata import compute_file_checksum


def test_clean_value_handles_none_and_empty():
    assert clean_value(None) is None
    assert clean_value("") is None
    assert clean_value("   ") is None
    assert clean_value("  valid_string  ") == "valid_string"
    assert clean_value("123.45") == "123.45"


def test_get_row_value_resolves_aliases():
    row = {
        "product_id": "prod_1",
        "product_name_lenght": "54",
        "product_description_lenght": "250",
    }
    assert _get_row_value(row, "product_id") == "prod_1"
    # Tests that 'product_name_length' successfully maps to 'product_name_lenght'
    assert _get_row_value(row, "product_name_length") == "54"
    assert _get_row_value(row, "product_description_length") == "250"
    assert _get_row_value(row, "nonexistent") is None


def test_validate_source_files_detects_missing():
    with tempfile.TemporaryDirectory() as tmpdir:
        # Create 2 out of 3 files
        open(os.path.join(tmpdir, "file_a.csv"), "w").close()
        open(os.path.join(tmpdir, "file_b.csv"), "w").close()

        sources = ["file_a.csv", "file_b.csv", "file_missing.csv"]
        missing = validate_source_files(tmpdir, sources)
        assert missing == ["file_missing.csv"]


def test_validate_source_files_all_present():
    with tempfile.TemporaryDirectory() as tmpdir:
        for f in REQUIRED_FILES:
            open(os.path.join(tmpdir, f), "w").close()

        missing = validate_source_files(tmpdir, REQUIRED_FILES)
        assert missing == []


def test_read_csv_rows_reads_dictionary():
    with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".csv") as fh:
        fh.write("col_a,col_b\n1,apple\n2,banana\n")
        fh_path = fh.name

    try:
        rows = list(read_csv_rows(fh_path))
        assert len(rows) == 2
        assert rows[0] == {"col_a": "1", "col_b": "apple"}
        assert rows[1] == {"col_a": "2", "col_b": "banana"}
    finally:
        os.remove(fh_path)


def test_file_checksum_is_deterministic():
    with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".csv") as fh:
        fh.write("test content for checksum")
        fh_path = fh.name

    try:
        sum1 = compute_file_checksum(fh_path)
        sum2 = compute_file_checksum(fh_path)
        assert sum1 == sum2
        assert len(sum1) == 64  # SHA-256 hex digest length
    finally:
        os.remove(fh_path)
