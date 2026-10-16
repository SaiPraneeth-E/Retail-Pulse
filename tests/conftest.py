"""RetailPulse test suite.

Unit tests run without production credentials or network access. External API
calls (Power BI refresh) are mocked.
"""

from __future__ import annotations

import os
import sys

# Ensure the repo root (and ingestion package) is importable when tests run
# from any working directory.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

import pytest
import psycopg2

@pytest.fixture
def psql_cursor():
    host = os.getenv("PGHOST", "localhost")
    port = int(os.getenv("PGPORT", "5433"))
    dbname = os.getenv("POSTGRES_DB", "retailpulse")
    user = os.getenv("POSTGRES_USER", "retailpulse")
    password = os.getenv("POSTGRES_PASSWORD", "changeme_in_env_file")
    
    conn = psycopg2.connect(
        host=host,
        port=port,
        dbname=dbname,
        user=user,
        password=password,
    )
    conn.autocommit = True
    cur = conn.cursor()
    yield cur
    cur.close()
    conn.close()

