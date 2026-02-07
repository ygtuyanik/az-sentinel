#!/bin/bash
# DHCP Audit Log setup - deploys both table and DCE/DCR
# Usage: ./deploy.sh <resource-group> <workspace-resource-id>

set -e

RG_NAME="${1:-}"
WORKSPACE_ID="${2:-}"

if [[ -z "$RG_NAME" || -z "$WORKSPACE_ID" ]]; then
  echo "Usage: $0 <resource-group> <workspace-resource-id>"
  echo "Example: $0 myrg \"/subscriptions/.../resourceGroups/cwrg01/providers/Microsoft.OperationalInsights/workspaces/cwlaw01\""
  exit 1
fi

echo "Step 1: Creating DHCP table..."
./create-dhcp-table.sh "$WORKSPACE_ID"

echo "Step 2: Deploying DCE and DCR..."
az deployment group create \
  --resource-group "$RG_NAME" \
  --template-file arm/azuredeploy.json \
  --parameters logAnalyticsWorkspaceResourceId="$WORKSPACE_ID" \
  --output none

echo "Done! DHCP audit log collection is now configured."
