#!/bin/bash
# DHCP Audit Log tablosunu Azure CLI REST API ile oluşturur
# Kullanım: ./create-dhcp-table.sh <workspace-resource-id>

set -e

WORKSPACE_RESOURCE_ID="${1:-}"
if [[ -z "$WORKSPACE_RESOURCE_ID" ]]; then
  echo "Hata: Workspace Resource ID gerekli"
  echo "Kullanım: $0 <workspace-resource-id>"
  echo "Örnek: $0 \"/subscriptions/.../resourceGroups/cwrg01/providers/Microsoft.OperationalInsights/workspaces/cwlaw01\""
  exit 1
fi

# Resource ID'den bilgileri çıkar
SUB_ID=$(echo "$WORKSPACE_RESOURCE_ID" | cut -d'/' -f3)
RG_NAME=$(echo "$WORKSPACE_RESOURCE_ID" | cut -d'/' -f5)
WORKSPACE_NAME=$(echo "$WORKSPACE_RESOURCE_ID" | cut -d'/' -f9)
TABLE_NAME="DHCPAuditLog_CL"
TABLE_FULL_NAME="${WORKSPACE_NAME}/${TABLE_NAME}"

echo "Workspace: $WORKSPACE_NAME"
echo "Resource Group: $RG_NAME"
echo "Table: $TABLE_FULL_NAME"
echo ""

# Tablo oluştur
echo "Tablo oluşturuluyor..."
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.OperationalInsights/workspaces/${WORKSPACE_NAME}/tables/${TABLE_NAME}?api-version=2022-10-01" \
  --body '{
    "properties": {
      "schema": {
        "name": "DHCPAuditLog_CL",
        "columns": [
          { "name": "TimeGenerated", "type": "datetime" },
          { "name": "Computer", "type": "string" },
          { "name": "EventId", "type": "string" },
          { "name": "LogDate", "type": "string" },
          { "name": "LogTime", "type": "string" },
          { "name": "Description", "type": "string" },
          { "name": "IpAddress", "type": "string" },
          { "name": "HostName", "type": "string" },
          { "name": "MacAddress", "type": "string" },
          { "name": "RawData", "type": "string" }
        ]
      },
      "retentionInDays": 90,
      "plan": "Analytics"
    }
  }' || {
  echo "Tablo zaten mevcut veya oluşturulamadı. Devam ediliyor..."
}

echo "Tablo hazır: $TABLE_FULL_NAME"
