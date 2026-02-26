# Imperva WAF Cloud - Azure Sentinel Connector

Imperva WAF Cloud loglarini Azure Sentinel'e (CommonSecurityLog tablosuna) aktaran Azure Function App.

## Mimari

```
Imperva WAF Cloud API  --->  Azure Function App (Timer: 10dk)  --->  Azure Monitor Ingestion API
                                      |                                       |
                                      v                                       v
                              State (File Share)                   DCE --> DCR --> CommonSecurityLog
```

## On Kosullar

| Gereksinim | Aciklama | Cloud Shell |
|---|---|---|
| Azure CLI (`az`) | Kurulu ve login olmus | Varsayilan kurulu |
| Azure Subscription | Contributor + User Access Administrator | - |
| Log Analytics Workspace | Sentinel etkinlestirilmis | - |
| Imperva API Bilgileri | API ID, API Key, Log Server URI | - |
| `zip` ve `jq` | Deploy script icin | Varsayilan kurulu |

> **Not:** Azure Functions Core Tools (`func`) gerekli **degildir**. Script, Cloud Shell ortamini otomatik algilar ve `az cli + zip` ile deploy eder. Ek kurulum gerekmez.

## Hizli Baslangic

### 1. Imperva API Bilgilerini Alin

Imperva Cloud WAF Console'dan:
- **API ID**: Account Settings > API Keys
- **API Key**: Account Settings > API Keys
- **Log Server URI**: SIEM Integration sayfasindan (format: `https://logs1.incapsula.com/<account_id>/`)

### 2. Log Analytics Workspace Resource ID'sini Alin

```bash
az monitor log-analytics workspace show \
  --resource-group <RG_ADI> \
  --workspace-name <WORKSPACE_ADI> \
  --query id -o tsv
```

### 3. parameters.json Dosyasini Doldurun

`parameters.json` dosyasindaki placeholder'lari gercek degerlerle degistirin:

| Parametre | Deger | Ornek |
|---|---|---|
| `LogAnalyticsWorkspaceResourceID` | Workspace Resource ID | `/subscriptions/.../workspaces/myworkspace` |
| `ImpervaAPIID` | Imperva API ID | `12345678901234` |
| `ImpervaAPIKey` | Imperva API Key | `abcdef12-3456-...` |
| `ImpervaLogServerURI` | Imperva Log Server URI | `https://logs1.incapsula.com/123456/` |

Opsiyonel parametreler (varsayilan degerlerle gelir):

| Parametre | Varsayilan | Aciklama |
|---|---|---|
| `FunctionName` | `ImpervaWAF` | Function App adi (prefix) |
| `DCEName` | `dce-imperva-waf` | Data Collection Endpoint adi |
| `DCRName` | `dcr-imperva-waf` | Data Collection Rule adi |
| `DCRStreamName` | `Custom-ImpervaWAFCloud_CL` | Custom stream adi |
| `OutputStreamName` | `Microsoft-CommonSecurityLog` | Hedef tablo |

### 4. Deploy Edin

#### Yerel Makineden

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
./deploy.sh <RESOURCE_GROUP> <LOCATION>
```

#### Azure Cloud Shell'den

```bash
# 1. ZIP'i Cloud Shell'e yukleyin (Upload dugmesi)
# 2. Acin
cd ~
unzip imperva-waf-sentinel-*.zip
cd imperva-waf-sentinel

# 3. parameters.json'i doldurun
nano parameters.json

# 4. Deploy edin
bash deploy.sh <RESOURCE_GROUP> <LOCATION>
```

Script ortami otomatik algilar:
- `func` CLI varsa (yerel) -> `func azure functionapp publish` kullanir
- `func` yoksa (Cloud Shell) -> `az functionapp deployment source config-zip --build-remote` kullanir

Her iki durumda da:
1. Resource Group olusturur (yoksa)
2. ARM Template ile altyapi deploy eder (Storage, Function App, DCE, DCR, Role Assignment)
3. Function kodunu remote build ile deploy eder
4. Deployment'i dogrular

## Olusturulan Azure Kaynaklari

| Kaynak | Tur | Aciklama |
|---|---|---|
| Function App | `Microsoft.Web/sites` | Python 3.11, Linux, Timer Trigger (10dk) |
| Storage Account | `Microsoft.Storage/storageAccounts` | Function App storage + state yonetimi |
| Application Insights | `Microsoft.Insights/components` | Izleme ve loglama |
| Data Collection Endpoint | `Microsoft.Insights/dataCollectionEndpoints` | Ingestion API endpoint |
| Data Collection Rule | `Microsoft.Insights/dataCollectionRules` | CEF -> CommonSecurityLog donusumu |
| Role Assignment | `Microsoft.Authorization/roleAssignments` | Monitoring Metrics Publisher |

## Dogrulama

### Function App'in Calistigini Kontrol Edin

```bash
# Function App durumu
az functionapp show --name <FUNCTION_APP_ADI> --resource-group <RG> --query state -o tsv

# Function App loglari (son 30dk)
az functionapp log tail --name <FUNCTION_APP_ADI> --resource-group <RG>
```

### Sentinel'de Veri Kontrolu

CommonSecurityLog tablosunda Imperva verilerinin gorunmesini bekleyin (ilk veri 10-20 dakika surebilir):

```kql
CommonSecurityLog
| where DeviceVendor == "Imperva"
| order by TimeGenerated desc
| take 20
| project TimeGenerated, DeviceVendor, DeviceProduct, Activity,
          SourceIP, DestinationIP, RequestURL, Message
```

## Sorun Giderme

### Function App Calismiyorsa

```bash
# App settings kontrol
az functionapp config appsettings list --name <FUNCTION_APP_ADI> --resource-group <RG> -o table

# Function listesi
az functionapp function list --name <FUNCTION_APP_ADI> --resource-group <RG> -o table
```

### Imperva API Hatasi (401/404)

- API ID ve API Key'in dogru oldugunu kontrol edin
- Log Server URI'nin sonunda `/` oldugunu kontrol edin
- Imperva Console'da SIEM integration'in aktif oldugunu dogrulayin

### Ingestion API Hatasi

- DCE ve DCR kaynaklarinin olusturulup olusturulmadigini kontrol edin
- Function App'in Managed Identity'sinin DCR uzerinde "Monitoring Metrics Publisher" rolune sahip oldugunu kontrol edin

```bash
# DCE kontrol
az monitor data-collection endpoint show --name <DCE_ADI> --resource-group <RG>

# DCR kontrol
az monitor data-collection rule show --name <DCR_ADI> --resource-group <RG>
```

### CommonSecurityLog'da Veri Yoksa

- DCR'deki transformKql'i kontrol edin
- DCR'nin dogru workspace'e baglandigini dogrulayin
- Function App loglarinda "Ingestion API ile chunk gonderildi" mesajini arayin

## Dosya Yapisi

```
impervaWaf/
├── deploy.sh                        # Ana deploy scripti
├── template.json                    # ARM template (altyapi tanimlamalari)
├── parameters.json                  # Musteri parametreleri (DOLDURUN)
├── check-logs.kql                   # Application Insights KQL sorgulari
├── DEPLOYMENT.md                    # Bu dosya
└── ImpervaWAFCloudSentinelConn/     # Function App kodu
    ├── host.json
    ├── requirements.txt
    └── ImpervaWAFCloudSentinelConnector/
        ├── __init__.py              # Ana function kodu
        ├── function.json            # Timer trigger tanimlamasi
        └── state_manager.py         # Son islenen dosya takibi
```

## Environment Variables (Referans)

ARM template tarafindan otomatik ayarlanir:

| Degisken | Aciklama | Otomatik |
|---|---|---|
| `ImpervaAPIID` | Imperva API ID | Evet |
| `ImpervaAPIKey` | Imperva API Key | Evet |
| `ImpervaLogServerURI` | Imperva Log Server URI | Evet |
| `AzureWebJobsStorage` | Storage connection string | Evet |
| `DCE_ENDPOINT` | Data Collection Endpoint URL | Evet |
| `DCR_IMMUTABLE_ID` | Data Collection Rule Immutable ID | Evet |
| `DCR_STREAM_NAME` | Custom stream adi | Evet |

Opsiyonel (test/debug icin):

| Degisken | Aciklama | Varsayilan |
|---|---|---|
| `DRY_RUN` | `true` ise Sentinel'e gondermez | `false` |
| `MAX_FILES` | Islenecek max dosya sayisi limiti | (yok - tumunu isler) |
