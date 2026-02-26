source ./parameters.sh

EXPORT_FILE="${1:-$HOME/analytics_rules_export.json}"
ERROR_LOG=~/import_errors.log

if [[ ! -f "$EXPORT_FILE" ]]; then
    echo "Hata: $EXPORT_FILE bulunamadı."
    exit 1
fi

TOKEN=$(az account get-access-token --query accessToken -o tsv)
TOKEN_EXPIRY=$(az account get-access-token --query expiresOn -o tsv)

refresh_token_if_needed() {
    local NOW=$(date -u +%s)
    local EXPIRY=$(date -u -d "$TOKEN_EXPIRY" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d %H:%M:%S" "$TOKEN_EXPIRY" +%s)
    if (( EXPIRY - NOW < 300 )); then
        echo "  [Token yenileniyor...]"
        TOKEN=$(az account get-access-token --query accessToken -o tsv)
        TOKEN_EXPIRY=$(az account get-access-token --query expiresOn -o tsv)
    fi
}

TOTAL=$(jq '.value | length' "$EXPORT_FILE")
echo "Toplam kural: $TOTAL — Import başlıyor..."
echo "Hedef: $DEST_WORKSPACE ($DEST_RESOURCE_GROUP)"
echo ""

> "$ERROR_LOG"
SUCCESS=0
FAIL=0
i=0

jq -c '.value[]' "$EXPORT_FILE" | while read -r rule; do
    i=$((i + 1))
    RULE_ID=$(echo "$rule" | jq -r '.name')
    DISPLAY_NAME=$(echo "$rule" | jq -r '.properties.displayName')
    RULE_KIND=$(echo "$rule" | jq -r '.kind')

    if [[ "$RULE_KIND" == "Fusion" || "$RULE_KIND" == "MLBehaviorAnalytics" ]]; then
        echo "[$i/$TOTAL] SKIP [$RULE_KIND] $DISPLAY_NAME"
        continue
    fi

    refresh_token_if_needed

    URI="https://management.azure.com/subscriptions/$DEST_SUBSCRIPTION_ID/resourceGroups/$DEST_RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$DEST_WORKSPACE/providers/Microsoft.SecurityInsights/alertRules/$RULE_ID?api-version=2025-09-01"

    CLEAN_RULE=$(echo "$rule" | jq 'del(.id, .properties.lastModifiedUtc)')

    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$CLEAN_RULE" "$URI")

    if [[ "$HTTP_STATUS" == "200" || "$HTTP_STATUS" == "201" ]]; then
        echo "[$i/$TOTAL] OK  $DISPLAY_NAME"
    else
        echo "[$i/$TOTAL] ERR [$HTTP_STATUS] $DISPLAY_NAME" | tee -a "$ERROR_LOG"
    fi

    sleep 0.5
done

echo ""
echo "Tamamlandı."
if [[ -s "$ERROR_LOG" ]]; then
    echo "Hatalar: $ERROR_LOG"
else
    echo "Hata yok."
fi
