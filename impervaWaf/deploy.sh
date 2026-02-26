#!/bin/bash
# ============================================================================
# Imperva WAF Cloud Sentinel Connector - Deploy Script
# ============================================================================
# Kullanim:
#   ./deploy.sh <resource-group> <location>
#
# Ornek:
#   ./deploy.sh rg-sentinel-imperva northeurope
#
# Hem yerel makineden hem Azure Cloud Shell'den calisir.
# On kosullar:
#   - Azure CLI (az) kurulu ve login olmus olmali
#   - parameters.json doldurulmus olmali
# ============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo -e "${BLUE}[STEP]${NC}  $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RESOURCE_GROUP="${1:-}"
LOCATION="${2:-}"
TEMPLATE_FILE="$SCRIPT_DIR/template.json"
PARAMETERS_FILE="$SCRIPT_DIR/parameters.json"
CODE_DIR="$SCRIPT_DIR/ImpervaWAFCloudSentinelConn"

# ---- Parametre kontrolu ----
if [[ -z "$RESOURCE_GROUP" || -z "$LOCATION" ]]; then
    echo ""
    echo "Imperva WAF Cloud Sentinel Connector - Deploy Script"
    echo ""
    echo "Kullanim: $0 <resource-group> <location>"
    echo ""
    echo "Ornek:"
    echo "  $0 rg-sentinel-imperva northeurope"
    echo "  $0 rg-sentinel-imperva westeurope"
    echo ""
    echo "On kosullar:"
    echo "  1. parameters.json dosyasini doldurun"
    echo "  2. Azure CLI ile login olun: az login"
    echo ""
    exit 1
fi

echo ""
info "============================================================"
info " Imperva WAF Cloud Sentinel Connector - Deploy"
info "============================================================"
info ""
info "Resource Group : $RESOURCE_GROUP"
info "Location       : $LOCATION"
info ""

# ---- On kontroller ----
step "On kontroller yapiliyor..."

if ! command -v az &>/dev/null; then
    error "Azure CLI (az) bulunamadi!"
    error "Kurulum: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

if ! az account show &>/dev/null; then
    error "Azure'a login olunmamis. Calistirin: az login"
    exit 1
fi

SUBSCRIPTION=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
info "Subscription: $SUBSCRIPTION ($SUBSCRIPTION_ID)"

# Deploy yontemi sec
USE_FUNC_CLI=false
if command -v func &>/dev/null; then
    USE_FUNC_CLI=true
    info "Deploy yontemi: func CLI (Azure Functions Core Tools)"
elif command -v zip &>/dev/null; then
    info "Deploy yontemi: az CLI + zip (Cloud Shell uyumlu)"
else
    error "'func' veya 'zip' bulunamadi. Birini kurun:"
    error "  func: npm install -g azure-functions-core-tools@4"
    error "  zip:  sudo apt install zip"
    exit 1
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    error "Template dosyasi bulunamadi: $TEMPLATE_FILE"
    exit 1
fi

if [[ ! -f "$PARAMETERS_FILE" ]]; then
    error "Parameters dosyasi bulunamadi: $PARAMETERS_FILE"
    error "parameters.json dosyasini doldurup tekrar deneyin."
    exit 1
fi

if [[ ! -d "$CODE_DIR" ]]; then
    error "Function kodu bulunamadi: $CODE_DIR"
    exit 1
fi

# parameters.json'da placeholder kontrolu
if grep -q '<IMPERVA_API_ID>\|<IMPERVA_API_KEY>\|<IMPERVA_LOG_SERVER_URI>\|<LOG_ANALYTICS_WORKSPACE_RESOURCE_ID>' "$PARAMETERS_FILE"; then
    error "parameters.json'da doldurulmamis degerler var!"
    error "Lutfen asagidaki degerleri doldurun:"
    grep -n '<.*>' "$PARAMETERS_FILE" | while read -r line; do
        error "  $line"
    done
    exit 1
fi

info "On kontroller basarili"
echo ""

# ---- 1. Resource Group ----
step "[1/4] Resource Group kontrol ediliyor..."
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    info "Resource Group olusturuluyor: $RESOURCE_GROUP ($LOCATION)"
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
    info "Resource Group olusturuldu"
else
    info "Resource Group zaten mevcut: $RESOURCE_GROUP"
fi
echo ""

# ---- 2. ARM Template Deploy ----
step "[2/4] ARM Template deploy ediliyor (altyapi + DCE + DCR + Function App)..."
info "Bu islem 3-5 dakika surebilir..."

DEPLOY_OUTPUT=$(az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE" \
    --output json 2>&1)

DEPLOY_EXIT=$?
if [[ $DEPLOY_EXIT -ne 0 ]]; then
    error "ARM Template deploy basarisiz!"
    echo "$DEPLOY_OUTPUT"
    exit 1
fi

FUNCTION_APP_NAME=$(echo "$DEPLOY_OUTPUT" | jq -r '.properties.outputs.functionAppName.value // empty' 2>/dev/null)
DCE_ENDPOINT=$(echo "$DEPLOY_OUTPUT" | jq -r '.properties.outputs.dceEndpoint.value // empty' 2>/dev/null)
DCR_IMMUTABLE_ID=$(echo "$DEPLOY_OUTPUT" | jq -r '.properties.outputs.dcrImmutableId.value // empty' 2>/dev/null)
DCR_STREAM_NAME=$(echo "$DEPLOY_OUTPUT" | jq -r '.properties.outputs.dcrStreamName.value // empty' 2>/dev/null)

if [[ -z "$FUNCTION_APP_NAME" ]]; then
    info "Function App adi output'tan alinamadi, araniyor..."
    FUNCTION_APP_NAME=$(az functionapp list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null)
fi

if [[ -z "$FUNCTION_APP_NAME" ]]; then
    error "Function App bulunamadi!"
    exit 1
fi

info "ARM Template deploy basarili"
info "  Function App  : $FUNCTION_APP_NAME"
info "  DCE Endpoint  : $DCE_ENDPOINT"
info "  DCR Immutable : $DCR_IMMUTABLE_ID"
info "  DCR Stream    : $DCR_STREAM_NAME"
echo ""

# ---- 3. Function Code Deploy ----
step "[3/4] Function kodu deploy ediliyor (remote build)..."
info "Bu islem 1-2 dakika surebilir..."

if [[ "$USE_FUNC_CLI" == "true" ]]; then
    # func CLI ile deploy (onerilen)
    cd "$CODE_DIR"
    func azure functionapp publish "$FUNCTION_APP_NAME" --python --build remote 2>&1 | while IFS= read -r line; do
        if [[ "$line" == *"error"* || "$line" == *"Error"* || "$line" == *"ERROR"* ]]; then
            error "$line"
        elif [[ "$line" == *"Functions in"* || "$line" == *"Deployment successful"* || "$line" == *"Remote build succeeded"* ]]; then
            info "$line"
        fi
    done
    cd - > /dev/null
else
    # az CLI + zip ile deploy (Cloud Shell)
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    cp -r "$CODE_DIR"/* "$TEMP_DIR/" 2>/dev/null

    rm -rf "$TEMP_DIR"/.git \
           "$TEMP_DIR"/.venv \
           "$TEMP_DIR"/.python_packages \
           "$TEMP_DIR"/local.settings.json \
           "$TEMP_DIR"/proxies.json 2>/dev/null || true

    find "$TEMP_DIR" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
    find "$TEMP_DIR" -type f -name "*.pyc" -delete 2>/dev/null || true
    find "$TEMP_DIR" -type f -name ".DS_Store" -delete 2>/dev/null || true

    ZIP_FILE="/tmp/imperva-deploy-$(date +%s).zip"
    cd "$TEMP_DIR"
    zip -r "$ZIP_FILE" . -q
    cd - > /dev/null
    info "ZIP olusturuldu: $(du -h "$ZIP_FILE" | cut -f1)"

    az functionapp deployment source config-zip \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP_NAME" \
        --src "$ZIP_FILE" \
        --build-remote true \
        --timeout 600 \
        --output none

    rm -f "$ZIP_FILE"
fi

info "Function kodu deploy edildi"
echo ""

# ---- 4. Dogrulama ----
step "[4/4] Deployment dogrulaniyor..."

sleep 10

FUNC_STATE=$(az functionapp show \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "state" -o tsv 2>/dev/null)

if [[ "$FUNC_STATE" == "Running" ]]; then
    info "Function App durumu: Running"
else
    warn "Function App durumu: $FUNC_STATE (birkac dakika icinde Running olmali)"
fi

# Workspace bilgisini parameters.json'dan al
WORKSPACE_ID=$(jq -r '.parameters.LogAnalyticsWorkspaceResourceID.value' "$PARAMETERS_FILE" 2>/dev/null)
WORKSPACE_NAME=$(echo "$WORKSPACE_ID" | grep -oP '[^/]+$')

echo ""
info "============================================================"
info " DEPLOY BASARILI"
info "============================================================"
info ""
info "Function App   : $FUNCTION_APP_NAME"
info "Function URL   : https://${FUNCTION_APP_NAME}.azurewebsites.net"
info "DCE Endpoint   : $DCE_ENDPOINT"
info "DCR Immutable  : $DCR_IMMUTABLE_ID"
info ""
info "Timer Trigger her 10 dakikada bir calisacak."
info "Ilk veriler 10-15 dakika icinde Sentinel'de gorunecek."
info ""
info "Dogrulama icin (10-15 dk sonra):"
info "  az monitor log-analytics query \\"
info "    --workspace \"\$(az monitor log-analytics workspace show -g $RESOURCE_GROUP -n $WORKSPACE_NAME --query customerId -o tsv)\" \\"
info "    --analytics-query \"CommonSecurityLog | where DeviceVendor == 'Imperva' | take 10\" \\"
info "    --output table"
info ""
info "============================================================"
