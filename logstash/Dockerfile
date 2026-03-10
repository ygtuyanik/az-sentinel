FROM docker.elastic.co/logstash/logstash:8.15.0

# Microsoft Sentinel DCR-based output plugin (Logs Ingestion API, no shared key needed)
RUN logstash-plugin install microsoft-sentinel-log-analytics-logstash-output-plugin

# netbase: Docker Lite Ubuntu'da getprotobyname_r hatasını önler
USER root
RUN apt-get install -y netbase --no-install-recommends
USER logstash
