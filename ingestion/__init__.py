"""RetailPulse ingestion package."""

from .config import IngestionConfig
from .ingest import run_ingestion

__all__ = ["IngestionConfig", "run_ingestion"]
