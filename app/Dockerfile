FROM python:3.13-slim
ARG APP_VERSION=dev
ARG ERROR_RATE=0
# VULN_DEMO=true deliberately installs a known-vulnerable library (PyYAML 5.3, CVE-2020-14343, CRITICAL, fixed in 5.4)
# so the pipeline's vulnerability gate can be shown blocking a build. Never true in a normal build.
ARG VULN_DEMO=false
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 APP_VERSION=${APP_VERSION} ERROR_RATE=${ERROR_RATE}
WORKDIR /srv
COPY requirements.txt .
RUN pip install -r requirements.txt && if [ "$VULN_DEMO" = "true" ]; then pip install "pyyaml==5.3"; fi
COPY main.py .
RUN useradd -r -u 10001 app
USER 10001
CMD ["gunicorn", "--bind=:8080", "--workers=1", "--threads=8", "main:app"]
