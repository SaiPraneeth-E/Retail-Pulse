"""Pytest fixtures for integration tests (require a live PostgreSQL)."""

from __future__ import annotations

import os

import psycopg2
import pytest


@pytest.fixture(scope="session")
def psql_conn():
    """Connect to PostgreSQL using environment variables."""
    conn = psycopg2.connect(
        host=os.getenv("PGHOST", "localhost"),
        port=int(os.getenv("PGPORT", "5432")),
        dbname=os.getenv("POSTGRES_DB", "retailpulse"),
        user=os.getenv("POSTGRES_USER", "retailpulse"),
        password=os.getenv("POSTGRES_PASSWORD", ""),
    )
    yield conn
    conn.close()


@pytest.fixture
def psql_cursor(psql_conn):
    with psql_conn.cursor() as cur:
        yield cur
    psql_conn.rollback()
