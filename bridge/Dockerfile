FROM python:3.12-slim

WORKDIR /srv
COPY bridge/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY bridge/app ./app
COPY bridge/migrations ./migrations

ENV PORT=8100
EXPOSE 8100
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
