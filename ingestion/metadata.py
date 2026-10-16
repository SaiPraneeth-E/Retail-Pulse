"""Ingestion metadata tracking: execution time, row counts, failures."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional


@dataclass
class FileRunResult:
    source_file: str
    target_table: str
    started_at: datetime
    finished_at: Optional[datetime] = None
    rows_read: int = 0
    rows_loaded: int = 0
    rows_rejected: int = 0
    status: str = "STARTED"  # STARTED, COMPLETED, FAILED
    error_message: Optional[str] = None
    file_checksum: Optional[str] = None

    @property
    def duration_seconds(self) -> Optional[float]:
        if self.finished_at is None:
            return None
        return (self.finished_at - self.started_at).total_seconds()

    def mark_completed(self) -> None:
        self.finished_at = datetime.now(timezone.utc)
        self.status = "COMPLETED"

    def mark_failed(self, error_message: str) -> None:
        self.finished_at = datetime.now(timezone.utc)
        self.status = "FAILED"
        self.error_message = error_message


def compute_file_checksum(path: str) -> str:
    """SHA-256 checksum of a file for change detection and audit."""
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()
