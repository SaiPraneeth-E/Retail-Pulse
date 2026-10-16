"""Power BI semantic-model refresh via the Power BI REST API (Entra ID).

Reads all configuration from environment variables. Never logs secrets or tokens.
Designed to be called only after ingestion, dbt transformations, and quality
checks have succeeded.
"""

from __future__ import annotations

import os
import time
from dataclasses import dataclass
from typing import Optional

import requests

from .logger import get_logger

logger = get_logger("retailpulse.ingestion.powerbi_refresh")

REQUIRED_ENV = [
    "POWERBI_TENANT_ID",
    "POWERBI_CLIENT_ID",
    "POWERBI_CLIENT_SECRET",
    "POWERBI_WORKSPACE_ID",
    "POWERBI_DATASET_ID",
]


@dataclass(frozen=True)
class PowerBIConfig:
    tenant_id: str
    client_id: str
    client_secret: str
    workspace_id: str
    dataset_id: str
    api_base: str
    timeout_seconds: int
    poll_interval_seconds: int

    @classmethod
    def from_env(cls) -> "PowerBIConfig":
        missing = [name for name in REQUIRED_ENV if not os.getenv(name)]
        if missing:
            raise ValueError(
                "Missing required Power BI configuration: "
                + ", ".join(missing)
                + ". Set these in .env (never commit real values)."
            )
        return cls(
            tenant_id=os.getenv("POWERBI_TENANT_ID", ""),
            client_id=os.getenv("POWERBI_CLIENT_ID", ""),
            client_secret=os.getenv("POWERBI_CLIENT_SECRET", ""),
            workspace_id=os.getenv("POWERBI_WORKSPACE_ID", ""),
            dataset_id=os.getenv("POWERBI_DATASET_ID", ""),
            api_base=os.getenv("POWERBI_API_BASE", "https://api.powerbi.com/v1.0/myorg"),
            timeout_seconds=int(os.getenv("POWERBI_REFRESH_TIMEOUT_SECONDS", "300")),
            poll_interval_seconds=int(
                os.getenv("POWERBI_REFRESH_POLL_INTERVAL_SECONDS", "15")
            ),
        )


@dataclass
class RefreshResult:
    requested: bool
    refresh_id: Optional[str]
    status: Optional[str]
    detail: str
    http_status: Optional[int] = None


class PowerBiRefreshError(RuntimeError):
    """Raised when a Power BI refresh request cannot be completed."""


def _get_access_token(config: PowerBIConfig) -> str:
    """Client-credentials flow with Microsoft Entra ID.

    Returns the access token. Secrets are never returned to the caller.
    """
    token_url = f"https://login.microsoftonline.com/{config.tenant_id}/oauth2/v2.0/token"
    data = {
        "grant_type": "client_credentials",
        "client_id": config.client_id,
        "client_secret": config.client_secret,
        "scope": "https://analysis.windows.net/powerbi/api/.default",
    }
    try:
        resp = requests.post(token_url, data=data, timeout=config.timeout_seconds)
    except requests.RequestException as exc:
        raise PowerBiRefreshError(f"Token request failed: {exc}") from exc

    if resp.status_code != 200:
        logger.error(
            "Authentication failed: HTTP %s", resp.status_code
        )
        raise PowerBiRefreshError(
            f"Authentication failed with HTTP {resp.status_code}"
        )
    try:
        return resp.json()["access_token"]
    except (ValueError, KeyError) as exc:
        raise PowerBiRefreshError("Authentication response missing access token") from exc


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def request_refresh(config: PowerBIConfig | None = None, poll: bool = False) -> RefreshResult:
    """Request a Power BI semantic-model refresh.

    Args:
        config: PowerBIConfig (loaded from env if None).
        poll: if True, poll refresh status until terminal state or timeout.

    Returns a RefreshResult. Secrets/tokens are never logged.
    """
    config = config or PowerBIConfig.from_env()
    token = _get_access_token(config)
    url = (
        f"{config.api_base}/workspaces/{config.workspace_id}"
        f"/datasets/{config.dataset_id}/refreshes"
    )

    try:
        resp = requests.post(url, headers=_headers(token), timeout=config.timeout_seconds)
    except requests.RequestException as exc:
        raise PowerBiRefreshError(f"Refresh request failed: {exc}") from exc

    # Handle common HTTP errors explicitly
    if resp.status_code == 401:
        raise PowerBiRefreshError("Refresh rejected: authentication/authorization failed (HTTP 401)")
    if resp.status_code == 403:
        raise PowerBiRefreshError("Refresh rejected: forbidden - check workspace access (HTTP 403)")
    if resp.status_code == 404:
        raise PowerBiRefreshError("Refresh rejected: workspace or dataset not found (HTTP 404)")
    if resp.status_code == 429:
        raise PowerBiRefreshError("Refresh rejected: throttled by Power BI (HTTP 429)")
    if resp.status_code == 409:
        raise PowerBiRefreshError(
            "Refresh rejected: a refresh is already in progress (HTTP 409 conflict)"
        )
    if resp.status_code not in (200, 202):
        logger.error("Refresh request failed: HTTP %s", resp.status_code)
        raise PowerBiRefreshError(
            f"Refresh request failed with HTTP {resp.status_code}"
        )

    refresh_id: Optional[str] = None
    try:
        body = resp.json()
        refresh_id = body.get("id")
    except ValueError:
        body = {}

    logger.info(
        "Refresh requested for dataset %s in workspace %s (HTTP %s)",
        config.dataset_id[:8] + "...",
        config.workspace_id[:8] + "...",
        resp.status_code,
    )

    if not poll:
        return RefreshResult(
            requested=True,
            refresh_id=refresh_id,
            status="requested",
            detail="Refresh accepted by Power BI API",
            http_status=resp.status_code,
        )

    # Poll until terminal state
    status_url = (
        f"{config.api_base}/workspaces/{config.workspace_id}"
        f"/datasets/{config.dataset_id}/refreshes/{refresh_id}"
    ) if refresh_id else None
    deadline = time.time() + config.timeout_seconds
    last_status = None
    while status_url and time.time() < deadline:
        try:
            status_resp = requests.get(status_url, headers=_headers(token), timeout=config.timeout_seconds)
        except requests.RequestException as exc:
            logger.warning("Status poll request failed: %s", exc)
            time.sleep(config.poll_interval_seconds)
            continue
        if status_resp.status_code != 200:
            logger.warning("Status poll returned HTTP %s", status_resp.status_code)
            time.sleep(config.poll_interval_seconds)
            continue
        try:
            last_status = status_resp.json().get("status")
        except ValueError:
            last_status = None
        logger.info("Refresh %s status: %s", refresh_id, last_status)
        if last_status in ("Completed", "Failed", "Cancelled"):
            return RefreshResult(
                requested=True,
                refresh_id=refresh_id,
                status=last_status,
                detail=f"Refresh reached terminal state: {last_status}",
                http_status=resp.status_code,
            )
        time.sleep(config.poll_interval_seconds)

    return RefreshResult(
        requested=True,
        refresh_id=refresh_id,
        status=last_status,
        detail="Polling timed out before terminal state",
        http_status=resp.status_code,
    )


def refresh_if_authorized(config: PowerBIConfig | None = None, poll: bool = False) -> RefreshResult:
    """Public entry point: validates config and requests a refresh.

    Intended to be invoked by the Airflow DAG only on pipeline success.
    """
    config = config or PowerBIConfig.from_env()
    logger.info(
        "Power BI refresh gate: tenant=*** client=*** workspace=*** dataset=***"
    )
    return request_refresh(config=config, poll=poll)


def main(argv: list[str] | None = None) -> int:
    import sys

    argv = list(sys.argv[1:] if argv is None else argv)
    poll = "--poll" in argv
    try:
        result = refresh_if_authorized(poll=poll)
        logger.info("Refresh result: %s (status=%s)", result.detail, result.status)
        return 0 if result.status in (None, "requested", "Completed") else 1
    except (ValueError, PowerBiRefreshError) as exc:
        logger.error("Power BI refresh failed: %s", exc)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
