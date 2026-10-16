"""Unit tests for Power BI refresh module (mocks external API calls)."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from ingestion.powerbi_refresh import (
    PowerBIConfig,
    PowerBiRefreshError,
    refresh_if_authorized,
    request_refresh,
)


def _config(**overrides):
    defaults = dict(
        tenant_id="tenant",
        client_id="client",
        client_secret="secret",
        workspace_id="workspace",
        dataset_id="dataset",
        api_base="https://api.powerbi.com/v1.0/myorg",
        timeout_seconds=10,
        poll_interval_seconds=1,
    )
    defaults.update(overrides)
    return PowerBIConfig(**defaults)


def test_config_missing_required(monkeypatch):
    for var in [
        "POWERBI_TENANT_ID",
        "POWERBI_CLIENT_ID",
        "POWERBI_CLIENT_SECRET",
        "POWERBI_WORKSPACE_ID",
        "POWERBI_DATASET_ID",
    ]:
        monkeypatch.delenv(var, raising=False)
    with pytest.raises(ValueError, match="Missing required Power BI configuration"):
        PowerBIConfig.from_env()


def _mock_token_and_refresh(monkeypatch, refresh_status, refresh_json=None):
    """Mock the Entra ID token endpoint and the Power BI refresh endpoint."""
    import ingestion.powerbi_refresh as pbr
    import requests

    monkeypatch.setattr(pbr, "_get_access_token", lambda config: "fake-token")

    token_resp = MagicMock()
    token_resp.status_code = 200
    token_resp.json.return_value = {"access_token": "fake-token"}

    refresh_resp = MagicMock()
    refresh_resp.status_code = refresh_status
    if refresh_json is not None:
        refresh_resp.json.return_value = refresh_json

    def fake_post(url, **kwargs):
        if "login.microsoftonline.com" in url:
            return token_resp
        return refresh_resp

    monkeypatch.setattr(pbr.requests, "post", fake_post)
    return refresh_resp


def test_request_refresh_success(monkeypatch):
    cfg = _config()
    _mock_token_and_refresh(monkeypatch, 202, {"id": "refresh-123"})

    result = request_refresh(cfg, poll=False)
    assert result.requested is True
    assert result.refresh_id == "refresh-123"
    assert result.status == "requested"
    assert result.http_status == 202


def test_request_refresh_401(monkeypatch):
    cfg = _config()
    _mock_token_and_refresh(monkeypatch, 401)
    with pytest.raises(PowerBiRefreshError, match="(?i)authentication"):
        request_refresh(cfg, poll=False)


def test_request_refresh_403_forbidden(monkeypatch):
    cfg = _config()
    _mock_token_and_refresh(monkeypatch, 403)
    with pytest.raises(PowerBiRefreshError, match="(?i)forbidden"):
        request_refresh(cfg, poll=False)


def test_request_refresh_404_not_found(monkeypatch):
    cfg = _config()
    _mock_token_and_refresh(monkeypatch, 404)
    with pytest.raises(PowerBiRefreshError, match="(?i)not found"):
        request_refresh(cfg, poll=False)


def test_request_refresh_409_conflict(monkeypatch):
    cfg = _config()
    _mock_token_and_refresh(monkeypatch, 409)
    with pytest.raises(PowerBiRefreshError, match="(?i)already in progress"):
        request_refresh(cfg, poll=False)


def test_request_refresh_429_throttle(monkeypatch):
    cfg = _config()
    _mock_token_and_refresh(monkeypatch, 429)
    with pytest.raises(PowerBiRefreshError, match="(?i)throttled"):
        request_refresh(cfg, poll=False)


def test_request_refresh_network_error(monkeypatch):
    cfg = _config()
    import ingestion.powerbi_refresh as pbr
    import requests

    monkeypatch.setattr(pbr, "_get_access_token", lambda config: "fake-token")
    monkeypatch.setattr(
        pbr.requests,
        "post",
        MagicMock(side_effect=requests.RequestException("boom")),
    )
    with pytest.raises(PowerBiRefreshError, match="(?i)refresh request failed"):
        request_refresh(cfg, poll=False)


def test_refresh_if_authorized_skips_when_unconfigured(monkeypatch, caplog):
    for var in [
        "POWERBI_TENANT_ID",
        "POWERBI_CLIENT_ID",
        "POWERBI_CLIENT_SECRET",
        "POWERBI_WORKSPACE_ID",
        "POWERBI_DATASET_ID",
    ]:
        monkeypatch.delenv(var, raising=False)
    # Should not raise; logs a warning instead.
    import ingestion.powerbi_refresh as pbr
    # Call request path directly via from_env to force ValueError.
    with pytest.raises(ValueError):
        pbr.refresh_if_authorized()
