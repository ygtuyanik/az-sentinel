# Imperva WAF Cloud → Sentinel Connector (Paketlenmiş)

Azure Sentinel [Imperva WAF Cloud connector](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions/ImpervaCloudWAF/Data%20Connectors/ImpervaWAFCloudSentinelConnector) tabanlı; **sadece whitelist alanları** Log Analytics’e göndererek ingestion maliyetini düşüren sürüm.

## Proje yapısı

```
ImpervaWAFCloudSentinelConnector/
├── host.json
├── requirements.txt
├── local.settings.json.example
├── README.md
└── ImpervaWAFTimerTrigger/
    ├── __init__.py      # Ana mantık + slim_event whitelist
    ├── function.json    # Timer trigger (her 10 dk)
    └── state_manager.py
```

## Gereksinimler

- Python 3.9 veya 3.10 (Azure Functions v4 önerilir)
- [Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local) (lokalde test için)
- Azure’da Function App (Linux veya Windows, Python runtime)

## Lokal kurulum

1. Bu klasörü aç:
   ```bash
   cd ImpervaWAFCloudSentinelConnector
   ```

2. Sanal ortam (isteğe bağlı):
   ```bash
   python -m venv .venv
   source .venv/bin/activate   # Linux/macOS
   # .venv\Scripts\activate    # Windows
   ```

3. Bağımlılıkları yükle:
   ```bash
   pip install -r requirements.txt
   ```

4. Ayarları kopyala ve düzenle:
   ```bash
   cp local.settings.json.example local.settings.json
   # WorkspaceID, WorkspaceKey, ImpervaAPIID, ImpervaAPIKey, ImpervaLogServerURI doldur
   ```

## Paketleme (kendi build’in)

### Yöntem 1: ZIP ile manuel paket

```bash
cd /home/yigitu/workbench/beymen_dcr/ImpervaWAFCloudSentinelConnector

# Bağımlılıkları proje köküne kur (Azure’un beklediği yapı)
pip install -r requirements.txt -t .

# Gereksiz dosyaları çıkar
rm -rf *.dist-info *.egg-info __pycache__ .venv
find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true

# ZIP oluştur (host.json + ImpervaWAFTimerTrigger/ + requirements’taki paketler)
zip -r ../ImpervaWAFConnector.zip . -x "*.pyc" -x ".git*" -x "local.settings.json" -x "*.md"
```

Oluşan `ImpervaWAFConnector.zip` dosyasını Azure’da “Deploy from zip” veya “Run from package” ile kullanabilirsin.

### Yöntem 2: Azure Functions Core Tools ile publish

```bash
cd /home/yigitu/workbench/beymen_dcr/ImpervaWAFCloudSentinelConnector

# Önce test
func start

# Deploy (FUNCTION_APP_NAME = kendi Function App adın)
func azure functionapp publish <FUNCTION_APP_NAME> --python
```

Bu komut uzaktaki Function App’e doğrudan deploy eder; paketi sen oluşturmazsın ama Azure otomatik paketler.

### Yöntem 3: VS Code

1. “Azure Functions” eklentisini kur.
2. Proje kökünü aç: `ImpervaWAFCloudSentinelConnector`.
3. F1 → “Azure Functions: Deploy to Function App” → abonelik ve Function App seç.

## Azure’da ayarlar (Application settings)

Function App → **Configuration** → **Application settings** içinde şunlar olmalı:

| Ayar | Açıklama |
|------|----------|
| `WorkspaceID` | Log Analytics workspace ID (GUID) |
| `WorkspaceKey` | Log Analytics primary/secondary key |
| `ImpervaAPIID` | Imperva API ID |
| `ImpervaAPIKey` | Imperva API key |
| `ImpervaLogServerURI` | Imperva log sunucu URI (örn. `https://...`) |
| `AzureWebJobsStorage` | Storage account connection string |

İsteğe bağlı:

- `logAnalyticsUri`: Özel LA endpoint (örn. sovereign cloud); yoksa `https://<WorkspaceID>.ods.opinsights.azure.com` kullanılır.

## Gönderilen alanlar (whitelist)

Log Analytics’e sadece aşağıdaki alanlar gider (tablo: `ImpervaWAFCloud_CL`).  
`TenantId`, `SourceSystem`, `Type`, `_ResourceId`, `TimeGenerated` platform tarafından eklenir.

- EventVendor_s, EventProduct_s, EventType_s, Device_Version_s  
- Rulename_s, Signature_s, Attack_Name_s, Attack_Severity_s  
- sourceServiceName_s, siteid_s, Customer_s, start_s, end_s  
- request_s, requestMethod_s, cn1_s, app_s, act_s, qstr_s, ref_s  
- sip_s, spt_s, in_s, xff_s, cpt_s, deviceExternalId_s, src_s  
- requestClientApplication_s, latitude_s, longitude_s  
- Computer, EventGeneratedTime  

Whitelist’i değiştirmek için `ImpervaWAFTimerTrigger/__init__.py` içindeki `TARGET_FIELDS` sözlüğünü güncelle.

## Notlar

- Timer varsayılan: her 10 dakikada bir (`0 */10 * * * *`). `function.json` içinden değiştirilebilir.
- İlk deploy sonrası Function App’i bir kez **Restart** etmek iyi olur.
- Kaynak: [Azure-Sentinel ImpervaWAFCloudSentinelConnector](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions/ImpervaCloudWAF/Data%20Connectors/ImpervaWAFCloudSentinelConnector).
