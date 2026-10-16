# RetailPulse — Power BI Integration Guide

This directory contains database views, DAX measures, dashboard specifications, and architectural documentation for connecting **Microsoft Power BI** to the RetailPulse data platform.

---

## Architecture Overview

```text
PostgreSQL (analytics schema)
     │
     ├── Direct Connection / DirectQuery ──► Power BI Desktop (Local Authoring)
     │
     └── On-Premises Data Gateway ─────────► Power BI Service (Cloud Workspace)
                                                    ▲
                                                    │ POST /refreshes
                                      Airflow (ingestion/powerbi_refresh.py)
```

---

## 1. Connecting Power BI Desktop Locally

1. Open **Power BI Desktop**.
2. Select **Get Data** > **PostgreSQL Database**.
3. Connection settings:
   - **Server**: `localhost:5432` (or `postgres:5432` if connecting from within Docker network)
   - **Database**: `retailpulse`
   - **Data Connectivity mode**: **Import** (recommended for star-schema performance) or **DirectQuery**
4. Authentication:
   - User Name: `powerbi_reader` (or `retailpulse` administrator)
   - Password: configured in `.env` (`POSTGRES_PASSWORD`)
5. In the Navigator dialog, select either:
   - The dimensional model tables: `analytics.dim_*` and `analytics.fact_*`
   - OR the ready-to-use reporting views: `analytics.vw_*`
6. Click **Load** to import data.

---

## 2. Setting Up Automatic Semantic Model Refresh

The module `ingestion/powerbi_refresh.py` triggers an automated semantic-model refresh using the official **Power BI REST API** via OAuth 2.0 client credentials.

### Prerequisites

1. **Power BI Service Workspace**:
   - Publish your `.pbix` file to a Power BI Workspace (e.g., `RetailPulse Analytics`).
2. **On-Premises Data Gateway**:
   - Because PostgreSQL runs on your local machine or private Docker network, Power BI Service (cloud) cannot reach it directly over the public internet.
   - Install the **On-Premises Data Gateway (Standard Mode)** on your host machine.
   - Register the Gateway in Power BI Service and configure the PostgreSQL connection data source.
   - *Note: If PostgreSQL is hosted on cloud services (AWS RDS, Azure Database for PostgreSQL, Supabase), a gateway is not required if public SSL access is enabled.*
3. **Microsoft Entra ID (Azure AD) App Registration**:
   - Navigate to the [Azure Portal](https://portal.azure.com) > **Microsoft Entra ID** > **App registrations**.
   - Create an app registration: `RetailPulse-Pipeline-Refresh`.
   - Under **API Permissions**, add **Power BI Service**:
     - Application Permission: `Dataset.ReadWrite.All`
     - Click **Grant admin consent for <Tenant>**.
   - Under **Certificates & secrets**, create a new Client Secret. Copy the secret value.
   - In **Power BI Admin Portal** > **Tenant settings** > **Developer settings**:
     - Enable: *"Allow service principals to use Power BI APIs"*.
     - Scope it to an Azure AD security group containing your app registration.
   - In your Power BI Workspace:
     - Add the Service Principal as an **Admin** or **Contributor** to the workspace.

---

## 3. Environment Variable Configuration

Add the following to your `.env` file:

```bash
# Microsoft Entra ID & Power BI Service
POWERBI_TENANT_ID=your-tenant-uuid
POWERBI_CLIENT_ID=your-app-registration-client-id
POWERBI_CLIENT_SECRET=your-app-secret-value
POWERBI_WORKSPACE_ID=your-workspace-guid
POWERBI_DATASET_ID=your-semantic-model-dataset-guid

# API Settings
POWERBI_API_BASE=https://api.powerbi.com/v1.0/myorg
POWERBI_REFRESH_TIMEOUT_SECONDS=300
POWERBI_REFRESH_POLL_INTERVAL_SECONDS=15
```

---

## 4. Pipeline Gating & Execution

The Airflow DAG (`airflow/dags/retailpulse_pipeline.py`) executes `refresh_powerbi_semantic_model` as **Task 8**:
- It runs **ONLY** after all upstream data ingestion, schema validation, dbt transformations, and data quality tests have completed with `SUCCEEDED` status.
- If upstream tasks fail, the refresh task is skipped, preventing stale or broken data from entering executive dashboards.
- If credentials are not set, the task logs a clear, safe warning and skips gracefully without failing the core data pipeline.

### Manual Refresh Command

You can run a refresh on-demand from the command line:

```powershell
python -m ingestion.powerbi_refresh
```

To request the refresh and poll until it reaches terminal status:

```powershell
python -m ingestion.powerbi_refresh --poll
```

---

## 5. Power BI Licensing & Refresh Limits

| License Type | Maximum Scheduled Refreshes | REST API Unlimited? | Gateway Support |
| :--- | :--- | :--- | :--- |
| **Power BI Pro** | 8 per day per dataset | Up to 8 calls/day | Supported |
| **Power BI Premium Per User (PPU)** | 48 per day per dataset | Up to 48 calls/day | Supported |
| **Fabric / Premium Capacity** | Unlimited (throttled by SKU) | Unlimited calls (FIFO queue) | Supported |

> **Important Distinction**: The REST API refreshes the published cloud **Semantic Model** in Power BI Service. It does **not** update open local `.pbix` authoring sessions in Power BI Desktop (Desktop requires clicking the local "Refresh" button in the Ribbon).
