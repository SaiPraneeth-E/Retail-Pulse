"""Integration-style tests that require a live PostgreSQL.

These are skipped unless RETAILPULSE_INTEGRATION=1 and a database is reachable.
"""

from __future__ import annotations

import os

import pytest

pytestmark = pytest.mark.skipif(
    os.getenv("RETAILPULSE_INTEGRATION") != "1",
    reason="Integration tests require RETAILPULSE_INTEGRATION=1 and a live PostgreSQL",
)


def test_schema_exists(psql_cursor):
    psql_cursor.execute(
        "SELECT schema_name FROM information_schema.schemata WHERE schema_name IN ('raw','staging','analytics','audit')"
    )
    found = {row[0] for row in psql_cursor.fetchall()}
    assert {"raw", "staging", "analytics", "audit"} <= found


def test_fact_orders_no_duplicate_revenue(psql_cursor):
    psql_cursor.execute("SELECT ROUND(COALESCE(SUM(order_revenue), 0)::numeric, 2) FROM analytics.fact_orders;")
    fact_rev = psql_cursor.fetchone()[0]

    psql_cursor.execute("SELECT ROUND(COALESCE(SUM(price::numeric), 0)::numeric, 2) FROM raw.olist_order_items_dataset;")
    raw_rev = psql_cursor.fetchone()[0]

    assert fact_rev > 0, "fact_orders revenue should be positive"
    assert fact_rev == raw_rev, f"fact_orders revenue ({fact_rev}) must match raw item prices ({raw_rev}) with 0 double counting"

