FROM python:3.12-slim

# openssh-client: a ponte SSH na VPS para provisionar instâncias Evolution
# por tenant (produto-05 seção 4, QR automático) — única camada do sistema
# com essa credencial.
RUN apt-get update && apt-get install -y --no-install-recommends openssh-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv
COPY bridge/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ReLttk (MIT, Linkmail16/ReLttk-TikTok-Client-Bot) fixado por commit; roda so dentro do worker
# por conta (subprocesso do gateway, sessao em diretorio proprio). Nao copiado para o repositorio.
ARG RELTTK_COMMIT=6483b27f441aaf13ebb3ad82b4c49014216a9733
RUN pip install --no-cache-dir websockets lz4 qrcode stealth-requests pycryptodome \
 && mkdir -p /opt/relttk && python -c "import io,tarfile,urllib.request,sys; \
u='https://github.com/Linkmail16/ReLttk-TikTok-Client-Bot/archive/%s.tar.gz' % sys.argv[1]; \
t=tarfile.open(fileobj=io.BytesIO(urllib.request.urlopen(u,timeout=60).read())); t.extractall('/opt/relttk'); \
import os; d=[x for x in os.listdir('/opt/relttk') if x.startswith('ReLttk')][0]; os.rename('/opt/relttk/'+d,'/opt/relttk/relttk')" ${RELTTK_COMMIT}
ENV PYTHONPATH=/opt/relttk

COPY bridge/app ./app
COPY bridge/migrations ./migrations
# worker de TikTok por conta (subprocesso do gateway; driver fake no simulador de QA)
COPY bridge/tiktok_worker ./tiktok_worker

ARG GIT_COMMIT=unknown
ENV GIT_COMMIT=${GIT_COMMIT}

RUN useradd --system --uid 10001 --create-home app \
 && mkdir -p /var/lib/luar/tiktok-sessions && chown -R app:app /srv /var/lib/luar
USER app

ENV PORT=8100
EXPOSE 8100

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["python", "-c", "import os,urllib.request;urllib.request.urlopen('http://127.0.0.1:%s/health' % os.environ.get('PORT','8100'), timeout=4)"]
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
