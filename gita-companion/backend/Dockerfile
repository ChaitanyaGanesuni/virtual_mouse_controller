# Gita Companion API. Build from the gita-companion/ directory:
#   docker build -f backend/Dockerfile -t gita-api .
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app

COPY backend/pyproject.toml backend/README.md ./
COPY backend/app ./app
RUN pip install --no-cache-dir -e .

COPY backend/alembic.ini backend/llm.yaml backend/docker-start.sh ./
COPY backend/migrations ./migrations
COPY content/data/gita.json ./content/gita.json

RUN useradd --uid 10001 --no-create-home app && chown -R app /app
USER app
EXPOSE 8000
CMD ["./docker-start.sh"]
