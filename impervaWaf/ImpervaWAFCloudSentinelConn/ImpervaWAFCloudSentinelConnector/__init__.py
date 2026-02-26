import requests
from requests.packages.urllib3.util.retry import Retry
import urllib3
import os
import zlib
import json
import azure.functions as func
import datetime
import re
import logging
from .state_manager import StateManager

from azure.monitor.ingestion import LogsIngestionClient
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

imperva_waf_api_id = None
imperva_waf_api_key = None
imperva_waf_log_server_uri = None
connection_string = None
dce_endpoint = None
dcr_immutable_id = None
dcr_stream_name = None
dry_run = False


def get_environment_variables():
    global imperva_waf_api_id, imperva_waf_api_key, imperva_waf_log_server_uri
    global connection_string, dce_endpoint, dcr_immutable_id, dcr_stream_name
    global dry_run

    imperva_waf_api_id = os.environ.get('ImpervaAPIID')
    imperva_waf_api_key = os.environ.get('ImpervaAPIKey')
    imperva_waf_log_server_uri = os.environ.get('ImpervaLogServerURI')
    connection_string = os.environ.get('AzureWebJobsStorage')
    dce_endpoint = os.environ.get('DCE_ENDPOINT')
    dcr_immutable_id = os.environ.get('DCR_IMMUTABLE_ID')
    dcr_stream_name = os.environ.get('DCR_STREAM_NAME', 'Custom-ImpervaWAFCloud_CL')
    dry_run = os.environ.get('DRY_RUN', '').lower() in ('true', '1', 'yes')

    logger.info("DCE_ENDPOINT: %s", dce_endpoint[:50] + "..." if dce_endpoint and len(dce_endpoint) > 50 else dce_endpoint)
    logger.info("DCR_IMMUTABLE_ID: %s", dcr_immutable_id[:50] + "..." if dcr_immutable_id and len(dcr_immutable_id) > 50 else dcr_immutable_id)
    logger.info("DCR_STREAM_NAME: %s", dcr_stream_name)

    if dry_run:
        logger.info("DRY_RUN modu aktif - veriler Sentinel'e gonderilmeyecek")

    if not imperva_waf_api_id:
        raise ValueError("ImpervaAPIID environment variable zorunludur")
    if not imperva_waf_api_key:
        raise ValueError("ImpervaAPIKey environment variable zorunludur")
    if not imperva_waf_log_server_uri:
        raise ValueError("ImpervaLogServerURI environment variable zorunludur")
    if not connection_string:
        raise ValueError("AzureWebJobsStorage environment variable zorunludur")
    if not dry_run:
        if not dce_endpoint:
            raise ValueError("DCE_ENDPOINT environment variable zorunludur")
        if not dcr_immutable_id:
            raise ValueError("DCR_IMMUTABLE_ID environment variable zorunludur")

    logger.info("Environment variables basariyla yuklendi")


class ImpervaFilesHandler:

    def __init__(self, api_id, api_key, log_server_uri, connection_string,
                 dce_endpoint, dcr_immutable_id, dcr_stream_name):
        self.url = log_server_uri
        self.api_id = api_id
        self.api_key = api_key
        self.connection_string = connection_string

        retries = Retry(
            total=3,
            status_forcelist={500, 429},
            backoff_factor=1,
            respect_retry_after_header=True
        )
        adapter = requests.adapters.HTTPAdapter(max_retries=retries)
        self.session = requests.Session()
        self.session.mount('https://', adapter)
        self.auth = urllib3.make_headers(basic_auth='{}:{}'.format(api_id, api_key))

        if dry_run:
            logger.info("DRY_RUN: Sentinel gonderimi devre disi")
            self.sentinel = DryRunSentinel()
        else:
            self.sentinel = ProcessToSentinel(dce_endpoint, dcr_immutable_id, dcr_stream_name)

        self.files_array = self.list_index_file()
        logger.info("Index file indirildi - %d dosya bulundu",
                     len(self.files_array) if self.files_array else 0)

    def list_index_file(self):
        files_array = []
        try:
            r = self.session.get(
                url="{}/{}".format(self.url, "logs.index"),
                headers=self.auth
            )
            if 200 <= r.status_code <= 299:
                logger.info("Index file basariyla indirildi")
                for line in r.iter_lines():
                    files_array.append(line.decode('UTF-8'))
                return files_array
            elif r.status_code == 401:
                logger.error("Imperva yetkilendirme hatasi (401) - API ID/Key kontrol edin")
            elif r.status_code == 404:
                logger.error("Index file bulunamadi (404) - LogServerURI kontrol edin")
            elif r.status_code == 429:
                logger.error("Rate limit asildi (429)")
            else:
                logger.error("Index file indirme hatasi: HTTP %s", r.status_code)
        except Exception as err:
            logger.error("Index file indirme exception: %s", err)

    def last_file_point(self):
        try:
            if self.files_array is None:
                return None

            max_files_env = os.environ.get('MAX_FILES')

            if dry_run:
                max_files = int(max_files_env or '3')
                files_arr = self.files_array[-max_files:]
                logger.info("[DRY_RUN] Son %d dosya secildi (toplam %d)",
                            len(files_arr), len(self.files_array))
                return files_arr

            files_arr = self.files_array
            try:
                state = StateManager(connection_string=self.connection_string)
                past_file = state.get()
                if past_file is not None:
                    logger.info("Son islenen dosya: %s", past_file)
                    try:
                        index = self.files_array.index(past_file)
                        files_arr = self.files_array[index + 1:]
                    except ValueError:
                        logger.warning("Son dosya index'te bulunamadi, tum dosyalar islenecek")
                        files_arr = self.files_array
            except Exception as state_err:
                logger.warning("State okuma hatasi: %s", state_err)

            if max_files_env:
                max_files = int(max_files_env)
                files_arr = files_arr[-max_files:]
                logger.info("MAX_FILES=%d limiti uygulandi", max_files)

            logger.info("Islenecek dosya sayisi: %d", len(files_arr))

            try:
                current_file = self.files_array[-1]
                state = StateManager(connection_string=self.connection_string)
                state.post(current_file)
            except Exception as state_err:
                logger.warning("State kaydetme hatasi: %s", state_err)

            return files_arr
        except Exception as err:
            logger.error("last_file_point hatasi: %s", err)

    def download_files(self):
        files_for_download = self.last_file_point()
        if files_for_download is not None:
            for file in files_for_download:
                logger.info("Dosya indiriliyor: %s", file)
                self.download_file(file)

    def download_file(self, file_name):
        try:
            r = self.session.get(
                url="{}/{}".format(self.url, file_name),
                stream=True,
                headers=self.auth
            )
            if 200 <= r.status_code <= 299:
                logger.info("Dosya indirildi: %s", file_name)
                self.decrypt_and_unpack_file(file_name, r.content)
                return r.status_code
            else:
                logger.error("Dosya indirme hatasi %s: HTTP %s", file_name, r.status_code)
        except Exception as err:
            logger.error("Dosya indirme exception %s: %s", file_name, err)

    def decrypt_and_unpack_file(self, file_name, file_content):
        file_splitted = file_content.split(b"|==|\n")
        file_header = file_splitted[0].decode("utf-8")
        file_data = file_splitted[1]
        file_encryption_flag = file_header.find("key:")

        events_arr = []
        events_data = None

        if file_encryption_flag == -1:
            try:
                events_data = zlib.decompressobj().decompress(file_data).decode("utf-8")
            except Exception as err:
                if 'incorrect header check' in str(err):
                    events_data = file_data.decode("utf-8")
                else:
                    logger.error("Decompress hatasi %s: %s", file_name, err)
        else:
            logger.warning("Sifrelenmis dosya atlaniyor: %s (encryption key gerekli)", file_name)
            return

        if events_data is not None:
            for line in events_data.splitlines():
                if "CEF" in line:
                    event_message = self.parse_cef(line)
                    events_arr.append(event_message)

        for chunk in self.gen_chunks_to_object(events_arr, chunksize=1000):
            self.sentinel.post_data(json.dumps(chunk), len(chunk), file_name)

    def parse_cef(self, cef_raw):
        rx = r'([^=\s\|]+)?=((?:[\\]=|[^=])+)(?:\s|$)'
        parsed_cef = {
            "EventVendor": "Imperva",
            "EventProduct": "Incapsula",
            "EventType": "SIEMintegration"
        }
        header_array = cef_raw.split('|')
        parsed_cef["Device Version"] = header_array[3]
        parsed_cef["Signature"] = header_array[4]
        parsed_cef["Attack Name"] = header_array[5]
        parsed_cef["Attack Severity"] = header_array[6]

        for key, val in re.findall(rx, cef_raw):
            if val.startswith('"') and val.endswith('"'):
                val = val[1:-1]
            parsed_cef[key] = val

        for elem in ['cs1', 'cs2', 'cs3', 'cs4', 'cs5', 'cs6']:
            try:
                if parsed_cef.get(elem) is not None:
                    label_key = '{}Label'.format(elem)
                    parsed_cef[parsed_cef[label_key].replace(" ", "")] = parsed_cef[elem]
                    parsed_cef.pop(label_key)
                    parsed_cef.pop(elem)
            except (KeyError, AttributeError):
                pass

        if parsed_cef.get('start'):
            try:
                ts = datetime.datetime.utcfromtimestamp(
                    int(parsed_cef['start']) / 1000.0
                ).isoformat()
                parsed_cef['EventGeneratedTime'] = ts
            except (ValueError, OSError):
                parsed_cef['EventGeneratedTime'] = ""
        else:
            parsed_cef['EventGeneratedTime'] = ""

        return parsed_cef

    def gen_chunks_to_object(self, object, chunksize=100):
        chunk = []
        for index, line in enumerate(object):
            if index % chunksize == 0 and index > 0:
                yield chunk
                del chunk[:]
            chunk.append(line)
        yield chunk


class DryRunSentinel:
    """Yerel test icin - verileri konsola yazdirir, Sentinel'e gondermez"""

    def post_data(self, body, chunk_count, file_name):
        events = json.loads(body)
        logger.info("[DRY_RUN] %d event - dosya: %s", chunk_count, file_name)
        for i, event in enumerate(events[:3]):
            logger.info("[DRY_RUN] Event %d: %s", i + 1, json.dumps(event, indent=2)[:500])
        if len(events) > 3:
            logger.info("[DRY_RUN] ... ve %d event daha", len(events) - 3)
        return True


class ProcessToSentinel:

    def __init__(self, dce_endpoint, dcr_immutable_id, dcr_stream_name):
        self.dce_endpoint = dce_endpoint
        self.dcr_immutable_id = dcr_immutable_id
        self.dcr_stream_name = dcr_stream_name

        # DefaultAzureCredential sirasyla dener:
        #   1. Environment variables (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET)
        #   2. Managed Identity (Azure Function App'te otomatik)
        #   3. Azure CLI (yerel testte az login ile)
        credential = DefaultAzureCredential()

        self.ingestion_client = LogsIngestionClient(
            endpoint=self.dce_endpoint,
            credential=credential
        )
        logger.info("Ingestion API baslatildi - DCE: %s", self.dce_endpoint)

    def post_data(self, body, chunk_count, file_name):
        try:
            events = json.loads(body)
            logs = []
            for event in events:
                if not event.get('EventGeneratedTime'):
                    event['EventGeneratedTime'] = datetime.datetime.utcnow().isoformat() + 'Z'
                logs.append(event)

            self.ingestion_client.upload(
                rule_id=self.dcr_immutable_id,
                stream_name=self.dcr_stream_name,
                logs=logs
            )

            logger.info("Sentinel'e gonderildi: %d event - dosya: %s", chunk_count, file_name)
            return True

        except Exception as e:
            logger.error("Ingestion API hatasi: %s - dosya: %s", str(e), file_name)
            raise


def main(mytimer: func.TimerRequest) -> None:
    try:
        logger.info("=" * 50)
        logger.info("Imperva WAF Cloud Sentinel Connector baslatiliyor...")

        if mytimer.past_due:
            logger.warning('Timer gecikti (past due)')

        get_environment_variables()

        ifh = ImpervaFilesHandler(
            api_id=imperva_waf_api_id,
            api_key=imperva_waf_api_key,
            log_server_uri=imperva_waf_log_server_uri,
            connection_string=connection_string,
            dce_endpoint=dce_endpoint,
            dcr_immutable_id=dcr_immutable_id,
            dcr_stream_name=dcr_stream_name
        )
        ifh.download_files()

        logger.info("Program basariyla tamamlandi")
        logger.info("=" * 50)

    except Exception as e:
        logger.error("Function hatasi: %s", str(e), exc_info=True)
        raise
