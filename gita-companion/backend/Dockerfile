# Gita Companion API. Build from the gita-companion/ directory:
#   docker build -f backend/Dockerfile -t gita-api .
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app

# Patched packaging tools (pip-audit flags the ones in the base image).
RUN pip install --no-cache-dir --upgrade pip setuptools

# Shared retrieval code (concept index, hybrid search) from the content package.
COPY content/pyproject.toml content/README.md ./content-pkg/
COPY content/gita_content ./content-pkg/gita_content
RUN pip install --no-cache-dir ./content-pkg

COPY backend/pyproject.toml backend/README.md ./
COPY backend/app ./app
RUN pip install --no-cache-dir -e .

COPY backend/alembic.ini backend/llm.yaml backend/docker-start.sh ./
COPY backend/migrations ./migrations
COPY content/data/gita.json ./content/gita.json

# The downloadable content pack (GET /v1/packs), built from the same dataset
# the database is seeded from, so phones can update their content offline-first.
COPY content/schema ./content-pkg/schema
RUN cd content-pkg && python -m gita_content.cli pack --dataset ../content/gita.json --pack ../packs/gita_content_pack.sqlite

RUN useradd --uid 10001 --no-create-home app && chown -R app /app
USER app
EXPOSE 8000
CMD ["./docker-start.sh"]
