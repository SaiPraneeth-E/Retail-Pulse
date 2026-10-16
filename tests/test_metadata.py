"""Unit tests for ingestion metadata helpers."""

from __future__ import annotations

import tempfile

from ingestion.metadata import FileRunResult, compute_file_checksum


def test_file_run_result_duration():
    from datetime import datetime, timedelta, timezone
    start = datetime.now(timezone.utc)
    r = FileRunResult(source_file="a.csv", target_table="raw.t", started_at=start)
    assert r.duration_seconds is None
    r.finished_at = start + timedelta(seconds=5)
    assert abs(r.duration_seconds - 5.0) < 0.01


def test_compute_file_checksum_deterministic():
    with tempfile.NamedTemporaryFile(delete=False, suffix=".csv") as fh:
        fh.write(b"order_id\n1\n")
        path = fh.name
    c1 = compute_file_checksum(path)
    c2 = compute_file_checksum(path)
    assert c1 == c2
    assert len(c1) == 64  # SHA-256 hex length
    os_unlink = __import__("os").unlink
    os_unlink(path)


def test_checksum_changes_on_content_change():
    with tempfile.NamedTemporaryFile(delete=False, suffix=".csv") as fh:
        fh.write(b"a\n")
        path = fh.name
    c1 = compute_file_checksum(path)
    with open(path, "ab") as fh:
        fh.write(b"b\n")
    c2 = compute_file_checksum(path)
    assert c1 != c2
    __import__("os").unlink(path)
