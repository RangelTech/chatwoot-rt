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

ENV PORT=8100
EXPOSE 8100
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
