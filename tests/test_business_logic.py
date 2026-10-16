"""Unit tests for business logic, metrics calculations, and join grain invariants."""

from __future__ import annotations

import pandas as pd
import pytest


def test_order_revenue_not_duplicated_by_payments():
    """Verify that orders with multiple payment installments do not multiply revenue.

    For example, an order with $100 in items split across 3 payment rows ($50, $30, $20)
    must still report exactly $100 order revenue, not $300.
    """
    order_items = pd.DataFrame([
        {"order_id": "ord_1", "order_item_id": 1, "price": 60.0, "freight": 10.0},
        {"order_id": "ord_1", "order_item_id": 2, "price": 40.0, "freight": 5.0},
    ])
    payments = pd.DataFrame([
        {"order_id": "ord_1", "payment_seq": 1, "value": 50.0},
        {"order_id": "ord_1", "payment_seq": 2, "value": 30.0},
        {"order_id": "ord_1", "payment_seq": 3, "value": 35.0},  # total 115 with freight
    ])

    # Correct aggregation at order grain:
    order_revenue = order_items.groupby("order_id")["price"].sum().iloc[0]
    assert order_revenue == 100.0

    # Bad practice (joining items directly to payments before aggregating):
    joined = pd.merge(order_items, payments, on="order_id")
    inflated_revenue = joined["price"].sum()
    assert inflated_revenue == 300.0  # 3x inflated! Demonstrates the anti-pattern

    # Correct grain separation prevents this inflation
    assert order_revenue != inflated_revenue


def test_delivery_delay_and_on_time_calculation():
    """Verify on-time delivery classification and delay day calculation."""
    def calculate_delivery(purchased, estimated, delivered):
        if delivered is None:
            return {"is_delivered": False, "is_late": False, "delay_days": None, "bucket": "In Transit"}
        
        delay_days = (pd.to_datetime(delivered) - pd.to_datetime(estimated)).days
        is_late = delay_days > 0
        if delay_days < 0:
            bucket = "Early"
        elif delay_days == 0:
            bucket = "On time"
        elif 1 <= delay_days <= 7:
            bucket = "1-7 days late"
        else:
            bucket = "8+ days late"

        return {
            "is_delivered": True,
            "is_late": is_late,
            "delay_days": delay_days,
            "bucket": bucket,
        }

    # Order delivered early
    early = calculate_delivery("2018-05-01", "2018-05-20", "2018-05-15")
    assert early["is_late"] is False
    assert early["delay_days"] == -5
    assert early["bucket"] == "Early"

    # Order delivered on time
    ontime = calculate_delivery("2018-05-01", "2018-05-15", "2018-05-15")
    assert ontime["is_late"] is False
    assert ontime["delay_days"] == 0
    assert ontime["bucket"] == "On time"

    # Order delivered 3 days late
    late = calculate_delivery("2018-05-01", "2018-05-15", "2018-05-18")
    assert late["is_late"] is True
    assert late["delay_days"] == 3
    assert late["bucket"] == "1-7 days late"


def test_on_time_delivery_rate_formula():
    """Verify that on-time delivery percentage is calculated correctly as on-time / delivered."""
    deliveries = pd.DataFrame([
        {"order_id": "o1", "is_delivered": True, "is_late": False},
        {"order_id": "o2", "is_delivered": True, "is_late": False},
        {"order_id": "o3", "is_delivered": True, "is_late": True},
        {"order_id": "o4", "is_delivered": False, "is_late": False}, # canceled/undelivered
    ])

    delivered = deliveries[deliveries["is_delivered"]]
    on_time = delivered[~delivered["is_late"]]
    on_time_pct = (len(on_time) / len(delivered)) * 100.0

    # 2 out of 3 delivered orders were on time = 66.67%
    assert round(on_time_pct, 2) == 66.67


def test_repeat_customer_rate_calculation():
    """Verify repeat customer metrics logic at unique customer grain."""
    orders = pd.DataFrame([
        {"customer_unique_id": "c1", "order_id": "o1"},
        {"customer_unique_id": "c1", "order_id": "o2"},
        {"customer_unique_id": "c2", "order_id": "o3"},
        {"customer_unique_id": "c3", "order_id": "o4"},
    ])

    order_counts = orders.groupby("customer_unique_id")["order_id"].nunique()
    total_customers = len(order_counts)
    repeat_customers = (order_counts > 1).sum()
    repeat_rate = (repeat_customers / total_customers) * 100.0

    assert total_customers == 3
    assert repeat_customers == 1
    assert round(repeat_rate, 2) == 33.33
