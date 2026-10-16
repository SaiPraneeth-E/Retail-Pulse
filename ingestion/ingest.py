"""Main ingestion entry point: validate, load, track metadata."""

from __future__ import annotations

import os
import sys
from datetime import datetime, timezone
from typing import List

import psycopg2

from .config import IngestionConfig
from .logger import get_logger
from .loader import FILE_TO_TABLE, LoadSummary, bulk_load, validate_source_files
from .metadata import FileRunResult, compute_file_checksum

logger = get_logger("retailpulse.ingestion")


def _connect(config: IngestionConfig):
    return psycopg2.connect(
        host=config.db_host,
        port=config.db_port,
        dbname=config.db_name,
        user=config.db_user,
        password=config.db_password,
    )


def _ensure_metadata_table(conn) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS audit.ingestion_log (
                ingestion_id       BIGSERIAL PRIMARY KEY,
                source_file        TEXT NOT NULL,
                target_table       TEXT NOT NULL,
                started_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
                finished_at        TIMESTAMPTZ,
                rows_read          INTEGER,
                rows_loaded        INTEGER,
                rows_rejected      INTEGER,
                status             TEXT NOT NULL,
                error_message      TEXT,
                file_checksum      TEXT
            );
            """
        )
    conn.commit()


def _record_result(conn, result: FileRunResult) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO audit.ingestion_log
                (source_file, target_table, started_at, finished_at,
                 rows_read, rows_loaded, rows_rejected, status,
                 error_message, file_checksum)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                result.source_file,
                result.target_table,
                result.started_at,
                result.finished_at,
                result.rows_read,
                result.rows_loaded,
                result.rows_rejected,
                result.status,
                result.error_message,
                result.file_checksum,
            ),
        )
    conn.commit()


def run_ingestion(config: IngestionConfig | None = None) -> List[FileRunResult]:
    """Run the full ingestion cycle.

    Returns a list of FileRunResult, one per source file. Raises SystemExit
    if required source files are missing (Airflow-friendly failure).
    """
    config = config or IngestionConfig.from_env()
    results: List[FileRunResult] = []

    missing = validate_source_files(config.data_dir, config.source_files)
    if missing:
        for filename in missing:
            logger.error("Required source file missing: %s", os.path.join(config.data_dir, filename))
        raise SystemExit(f"Missing required source files: {missing}")

    conn = _connect(config)
    try:
        _ensure_metadata_table(conn)

        for source_file in config.source_files:
            target_table = FILE_TO_TABLE[source_file]
            path = config.file_path(source_file)
            result = FileRunResult(
                source_file=source_file,
                target_table=target_table,
                started_at=datetime.now(timezone.utc),
                file_checksum=compute_file_checksum(path),
            )
            try:
                summary: LoadSummary = bulk_load(
                    conn,
                    source_file=source_file,
                    data_dir=config.data_dir,
                    batch_size=config.batch_size,
                )
                result.rows_read = summary.rows_read
                result.rows_loaded = summary.rows_loaded
                result.rows_rejected = summary.rows_rejected
                result.mark_completed()
                logger.info(
                    "Loaded %s -> %s: read=%d loaded=%d rejected=%d",
                    source_file,
                    target_table,
                    summary.rows_read,
                    summary.rows_loaded,
                    summary.rows_rejected,
                )
                if summary.rejected_reasons:
                    logger.warning(
                        "Rejection reasons for %s: %s",
                        source_file,
                        "; ".join(summary.rejected_reasons[:5]),
                    )
            except Exception as exc:  # noqa: BLE001
                result.mark_failed(str(exc))
                logger.error("Failed to load %s: %s", source_file, exc)
                # Do not silently continue: surface the failure to the caller
                raise
            finally:
                _record_result(conn, result)
                results.append(result)

        logger.info("Ingestion complete: %d files processed", len(results))
        return results
    finally:
        conn.close()


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    config = IngestionConfig.from_env()
    try:
        run_ingestion(config)
        return 0
    except SystemExit as exc:
        return int(exc.code) if isinstance(exc.code, int) else 1
    except Exception as exc:  # noqa: BLE001
        logger.error("Ingestion failed: %s", exc)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
