# Sentinel Analytics Rules Migration

Azure Sentinel analytics kurallarını bir Log Analytics workspace'inden diğerine taşımak için kullanılan script seti.

## Gereksinimler

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`)
- `jq`, `curl`
- Kaynak workspace üzerinde `Microsoft Sentinel Reader` yetkisi
- Hedef workspace üzerinde `Microsoft Sentinel Contributor` yetkisi

## Yapılandırma

`parameters.sh` dosyasını düzenle:

```bash
# Kaynak workspace
export SUBSCRIPTION_ID="<subscription-id>"
export RESOURCE_GROUP="<kaynak-resource-group>"
export WORKSPACE="<kaynak-workspace-adı>"

# Hedef workspace (farklı subscription olabilir)
export DEST_SUBSCRIPTION_ID="<hedef-subscription-id>"
export DEST_RESOURCE_GROUP="<hedef-resource-group>"
export DEST_WORKSPACE="<hedef-workspace-adı>"
```

> Kaynak ve hedef farklı subscription'larda olabilir. Aynıysa `DEST_SUBSCRIPTION_ID`'yi `SUBSCRIPTION_ID` ile aynı yapın.

## Kullanım

### 1. Export

Kaynak workspace'deki tüm analytics kurallarını dışa aktarır.

```bash
bash rule.export.sh
```

Çıktı: `~/analytics_rules_export.json`

### 2. Import

Export edilen kuralları hedef workspace'e yükler.

```bash
# Default dosyadan (~/.analytics_rules_export.json)
bash rule.import.sh

# Farklı dosyadan
bash rule.import.sh /path/to/dosya.json
```

Hatalı kurallar: `~/import_errors.log`

## Notlar

- `Fusion` ve `MLBehaviorAnalytics` türü kurallar Microsoft tarafından yönetilir, otomatik olarak atlanır.
- Import sırasında `id` ve `lastModifiedUtc` alanları temizlenerek gönderilir.
- Token süresi dolmak üzereyse import otomatik olarak yeniler (5 dakika eşiği).
- Azure Lighthouse üzerinden erişimde RBAC propagation 15-30 dakika sürebilir.
- API versiyonu: `2025-09-01`
