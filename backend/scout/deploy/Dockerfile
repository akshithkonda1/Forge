# ARIA Scout — the agentic research computer. Build context is the directory
# that CONTAINS backend/ (on the EC2 box: /opt/forge).
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# boto3 for Bedrock Converse (Grok). Everything else is stdlib.
RUN pip install --no-cache-dir "boto3>=1.34" \
    && useradd --system --uid 10001 scout

WORKDIR /app
COPY backend/__init__.py backend/_paths.py /app/backend/
COPY backend/scout /app/backend/scout
COPY backend/infra/lambda /app/backend/infra/lambda

USER scout
EXPOSE 8088
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8088/healthz',timeout=2)"
CMD ["python", "-m", "backend.scout"]
