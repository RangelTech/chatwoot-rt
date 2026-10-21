FROM python:3.12-slim

# openssh-client: a ponte SSH na VPS para provisionar instâncias Evolution
# por tenant (produto-05 seção 4, QR automático) — única camada do sistema
# com essa credencial.
RUN apt-get update && apt-get install -y --no-install-recommends openssh-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv
COPY bridge/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY bridge/app ./app
COPY bridge/migrations ./migrations
# worker de TikTok por conta (subprocesso do gateway; driver fake no simulador de QA)
COPY bridge/tiktok_worker ./tiktok_worker

ARG GIT_COMMIT=unknown
ENV GIT_COMMIT=${GIT_COMMIT}

RUN useradd --system --uid 10001 --create-home app && chown -R app:app /srv
USER app

ENV PORT=8100
EXPOSE 8100

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["python", "-c", "import os,urllib.request;urllib.request.urlopen('http://127.0.0.1:%s/health' % os.environ.get('PORT','8100'), timeout=4)"]
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
