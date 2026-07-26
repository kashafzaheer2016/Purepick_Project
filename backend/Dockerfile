# ══════════════════════════════════════════════════════════════
# PurePick Backend — Dockerfile
# Multi-stage aware, production-ready single image.
# The CMD can be overridden in docker-compose for each service
# (API, celery_ml worker, celery_default worker).
#
# Build context: ./backend/
# ══════════════════════════════════════════════════════════════

FROM python:3.11-slim AS base

# ── OS-level dependencies ──────────────────────────────────────────────────────
# libpq-dev + gcc       : psycopg2 (PostgreSQL adapter)
# libgl1 + libglib2.0-0 : OpenCV headless (skin analysis — no display needed)
# curl                  : Docker healthcheck inside container
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq-dev \
        gcc \
        libgl1 \
        libglib2.0-0 \
        curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ── Python dependencies ────────────────────────────────────────────────────────
# Copy requirements first so Docker caches this layer independently of source changes.
COPY requirements.txt .

# Install PyTorch CPU wheels first (large, separate layer → better cache hit rate)
RUN pip install --no-cache-dir \
        torch==2.1.2 \
        torchvision==0.16.2 \
        --index-url https://download.pytorch.org/whl/cpu

# Install remaining requirements (includes gunicorn, timm, albumentations, etc.)
RUN pip install --no-cache-dir -r requirements.txt

# ── Application source ─────────────────────────────────────────────────────────
COPY . .

# ── Runtime config ─────────────────────────────────────────────────────────────
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=purepick_core.settings.prod

# Shared scan upload directory (mounted as Docker volume in docker-compose)
RUN mkdir -p /app/scans /app/media /app/staticfiles \
    && chmod 777 /app/scans /app/media

# ── Non-root user for security ─────────────────────────────────────────────────
RUN useradd --create-home --shell /bin/bash purepick \
    && chown -R purepick:purepick /app
USER purepick

# ── Health check (API service) ─────────────────────────────────────────────────
# Only meaningful for the API container; Celery workers override CMD anyway.
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/api/health/ || exit 1

# ── Default command (overridden per-service in docker-compose or Railway) ───────
# • $PORT is provided by Railway/Heroku at runtime.
CMD ["sh", "-c", \
     "python manage.py migrate --noinput && \
      python manage.py collectstatic --noinput && \
      gunicorn purepick_core.wsgi:application \
        --bind 0.0.0.0:${PORT:-8000} \
        --workers 2 \
        --threads 4 \
        --timeout 120 \
        --access-logfile - \
        --error-logfile -"]
