# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **Azure Sentinel connector project** that integrates security data sources with Microsoft Azure Sentinel (SIEM). Three connectors exist:

1. **Imperva WAF Cloud** (`impervaWaf/`) — Azure Function App (Python) that polls Imperva API every 10 minutes and ingests CEF logs into Sentinel's `CommonSecurityLog` table.
2. **DHCP Audit Logs** (`dhcp/`) — ARM template + scripts that collect Windows DHCP server logs into a custom `DHCPAuditLog_CL` table via DCR.
3. **Shared DCR Templates** (`dcr/`) — Merged CEF+Syslog Data Collection Rule with KQL transformations.

## Deployment Commands

All deployment uses **Azure CLI** (`az`). No build step is needed for ARM templates or DCR JSON files.

### Imperva WAF Connector

```bash
# 1. Fill in configuration
nano impervaWaf/parameters.json
# Required fields: ImpervaAPIID, ImpervaAPIKey, ImpervaLogServerURI, LogAnalyticsWorkspaceResourceID

# 2. Deploy (creates RG, deploys ARM template, packages and publishes Python function)
./impervaWaf/deploy.sh <RESOURCE_GROUP_NAME> <LOCATION>
# Example:
./impervaWaf/deploy.sh rg-sentinel-imperva northeurope

# 3. Verify
az functionapp show --name <FUNCTION_APP_NAME> --resource-group <RG> --query state -o tsv
az functionapp log tail --name <FUNCTION_APP_NAME> --resource-group <RG>
```

### DHCP Audit Log Connector

```bash
WORKSPACE_ID="/subscriptions/{subId}/resourceGroups/{rgName}/providers/Microsoft.OperationalInsights/workspaces/{wsName}"
./dhcp/deploy.sh <RESOURCE_GROUP_NAME> "$WORKSPACE_ID"
```

### Debugging with KQL

Pre-written Application Insights KQL queries are in `impervaWaf/check-logs.kql`. Run them in the Azure Portal under Application Insights → Logs.

## Architecture

### Imperva WAF Data Flow

```
Imperva WAF Cloud API (gzipped CEF log files)
  → Azure Function (timer: every 10 min)
    ├─ State tracked in Azure File Share (avoids reprocessing)
    ├─ CEF parsed → structured JSON (1000-event chunks)
    └─ Azure Monitor Ingestion API
        → DCR (Data Collection Rule)
          → CommonSecurityLog table (Sentinel)
```

**Key implementation files:**
- `impervaWaf/ImpervaWAFCloudSentinelConn/ImpervaWAFCloudSentinelConnector/__init__.py` — Core logic: API polling, CEF parsing, chunked ingestion with retry/backoff
- `impervaWaf/ImpervaWAFCloudSentinelConn/ImpervaWAFCloudSentinelConnector/state_manager.py` — Stateful processing via Azure File Share
- `impervaWaf/ImpervaWAFCloudSentinelConn/ImpervaWAFCloudSentinelConnector/function.json` — Timer trigger config (`0 */10 * * * *`)
- `impervaWaf/template.json` — ARM template (Function App, Storage, DCE, DCR, Managed Identity role assignments)

### Authentication

Uses **Managed Identity** (`DefaultAzureCredential`) — no credentials in code. The ARM template creates and assigns the necessary roles automatically.

## Key Configuration

### Function App Environment Variables (set by ARM template)

| Variable | Purpose |
|---|---|
| `ImpervaAPIID` / `ImpervaAPIKey` | Imperva API credentials (basic auth) |
| `ImpervaLogServerURI` | Imperva log server endpoint |
| `DCE_ENDPOINT` | Data Collection Endpoint URL |
| `DCR_IMMUTABLE_ID` | Data Collection Rule ID |
| `DCR_STREAM_NAME` | Stream name (default: `Custom-ImpervaWAFCloud_CL`) |
| `DRY_RUN` | Set to `true` to test without sending to Sentinel |
| `MAX_FILES` | Limit files processed per run (useful for testing) |

## CEF Parsing

The Imperva connector parses CEF (Common Event Format) using regex `([^=\s\|]+)=((?:[\\]=|[^=])+)`. Custom fields `cs1`–`cs6` are renamed using their label fields. Unix timestamps are converted to ISO 8601. Encrypted files are skipped with a warning.

## Infrastructure as Code

- ARM templates (`template.json`, `dhcp/arm/azuredeploy.json`) define all Azure resources
- DCR JSON files (`dcr/syslog_cef.json`) contain KQL `transformKQL` expressions for log transformation
- `deploy.sh` scripts auto-detect environment (Azure Cloud Shell vs local with `func` CLI) and use the appropriate deployment path

## Python Dependencies (Imperva Function)

`azure-functions`, `requests`, `azure-storage-file-share`, `azure-monitor-ingestion`, `azure-identity`

Python 3.11+ required.
