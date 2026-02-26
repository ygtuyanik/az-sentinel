source ./parameters.sh
TOKEN=$(az account get-access-token --query accessToken -o tsv)

BASE_URI="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE/providers/Microsoft.SecurityInsights/alertRules"
API_VERSION="api-version=2025-09-01"

ALL_RULES="[]"
URI="$BASE_URI?$API_VERSION"

echo "Kurallar çekiliyor..."

while [[ -n "$URI" ]]; do
    RESPONSE=$(curl -s -X GET \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        "$URI")

    PAGE_RULES=$(echo "$RESPONSE" | jq '.value')
    ALL_RULES=$(echo "$ALL_RULES $PAGE_RULES" | jq -s '.[0] + .[1]')

    COUNT=$(echo "$PAGE_RULES" | jq 'length')
    echo "  $COUNT kural alındı..."

    URI=$(echo "$RESPONSE" | jq -r '.nextLink // empty')
done

TOTAL=$(echo "$ALL_RULES" | jq 'length')
echo "{\"value\": $ALL_RULES}" > ~/analytics_rules_export.json

echo "Tamamlandı. Toplam $TOTAL kural ~/analytics_rules_export.json dosyasına kaydedildi."
