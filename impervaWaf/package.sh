#!/bin/bash
# ============================================================================
# Imperva WAF Cloud Sentinel Connector - Musteri Dagitim Paketi Olusturma
# ============================================================================
# Bu script, musteriye teslim edilecek temiz bir ZIP paketi olusturur.
#
# Kullanim:
#   ./package.sh [cikti-dosyasi]
#
# Ornek:
#   ./package.sh                                    # imperva-waf-sentinel-YYYYMMDD.zip
#   ./package.sh imperva-connector-musteri-adi.zip  # ozel isim
# ============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATE_STAMP=$(date +%Y%m%d)
OUTPUT_FILE="${1:-$SCRIPT_DIR/imperva-waf-sentinel-${DATE_STAMP}.zip}"

# Mutlak path'e cevir
if [[ ! "$OUTPUT_FILE" =~ ^/ ]]; then
    OUTPUT_FILE="$SCRIPT_DIR/$OUTPUT_FILE"
fi

info "============================================================"
info " Imperva WAF Sentinel Connector - Paket Olusturuluyor"
info "============================================================"
info ""

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

PACKAGE_DIR="$TEMP_DIR/imperva-waf-sentinel"
mkdir -p "$PACKAGE_DIR/ImpervaWAFCloudSentinelConn/ImpervaWAFCloudSentinelConnector"

# Ana dosyalar
cp "$SCRIPT_DIR/deploy.sh"        "$PACKAGE_DIR/"
cp "$SCRIPT_DIR/template.json"    "$PACKAGE_DIR/"
cp "$SCRIPT_DIR/parameters.json"  "$PACKAGE_DIR/"
cp "$SCRIPT_DIR/DEPLOYMENT.md"    "$PACKAGE_DIR/"
cp "$SCRIPT_DIR/check-logs.kql"   "$PACKAGE_DIR/"

# Function App kodu
cp "$SCRIPT_DIR/ImpervaWAFCloudSentinelConn/host.json"       "$PACKAGE_DIR/ImpervaWAFCloudSentinelConn/"
cp "$SCRIPT_DIR/ImpervaWAFCloudSentinelConn/requirements.txt" "$PACKAGE_DIR/ImpervaWAFCloudSentinelConn/"

cp "$SCRIPT_DIR/ImpervaWAFCloudSentinelConn/ImpervaWAFCloudSentinelConnector/__init__.py"       "$PACKAGE_DIR/ImpervaWAFCloudSentinelConn/ImpervaWAFCloudSentinelConnector/"
cp "$SCRIPT_DIR/ImpervaWAFCloudSentinelConn/ImpervaWAFCloudSentinelConnector/function.json"     "$PACKAGE_DIR/ImpervaWAFCloudSentinelConn/ImpervaWAFCloudSentinelConnector/"
cp "$SCRIPT_DIR/ImpervaWAFCloudSentinelConn/ImpervaWAFCloudSentinelConnector/state_manager.py"  "$PACKAGE_DIR/ImpervaWAFCloudSentinelConn/ImpervaWAFCloudSentinelConnector/"

# Calistirma izinleri
chmod +x "$PACKAGE_DIR/deploy.sh"

# ZIP olustur
cd "$TEMP_DIR"
zip -r "$OUTPUT_FILE" "imperva-waf-sentinel/" -q
cd - > /dev/null

# Ozet
FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
FILE_COUNT=$(unzip -l "$OUTPUT_FILE" 2>/dev/null | tail -1 | awk '{print $2}')

info ""
info "Paket olusturuldu: $OUTPUT_FILE"
info "Boyut: $FILE_SIZE ($FILE_COUNT dosya)"
info ""
info "Paket icerigi:"
unzip -l "$OUTPUT_FILE" 2>/dev/null | grep -v "^Archive\|^$\|----\| files$" | awk '{print "  " $4}'
info ""
info "============================================================"
info " Musteri Talimatları:"
info "============================================================"
info ""
info "  1. ZIP'i acin"
info "  2. parameters.json dosyasini doldurun"
info "  3. ./deploy.sh <resource-group> <location> calistirin"
info ""
info "============================================================"
