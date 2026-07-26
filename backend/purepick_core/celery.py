"""
purepick_core/celery.py
=======================
Celery application factory.

Architecture:
  Django WSGI worker  →  receives HTTP request
                      →  enqueues task to Redis broker
                      →  returns task_id immediately (202 Accepted)

  Celery worker       →  picks up task from Redis
                      →  runs OCR / ML inference (blocking, CPU-heavy)
                      →  writes result back to Redis result backend
                      →  Flutter polls /api/task/<task_id>/ until done

WHY Celery + Redis instead of threading or asyncio:
  - Django's WSGI server is inherently synchronous. Running EasyOCR (3–8s)
    or ResNet-50 (5–15s) in a request handler blocks the entire worker thread.
  - Celery workers are separate processes — ML models load once per worker,
    not once per request. Memory-efficient under load.
  - Redis is already needed as a cache layer (Batch 4), so zero new infra.
"""
import os
from celery import Celery
from celery.signals import worker_process_init

# Default to dev settings; overridden by DJANGO_SETTINGS_MODULE env var
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'purepick_core.settings.dev')

app = Celery('purepick')

# Load Celery config from Django settings (CELERY_* namespace)
app.config_from_object('django.conf:settings', namespace='CELERY')

# Auto-discover tasks in all INSTALLED_APPS
# Looks for tasks.py in each app directory
app.autodiscover_tasks()


@worker_process_init.connect
def init_worker_process(**kwargs):
    """
    Runs in every forked worker process immediately after fork.
    Forces numpy, cv2, torch, and albumentations to fully initialise
    their C extensions before any task runs.

    Without this, Celery's prefork pool inherits partially-initialised
    C extension state from the parent process, causing:
      'numpy._core.multiarray failed to import'
      'cannot load module more than once per process'
    """
    try:
        import numpy as _np          # noqa: F401
        import cv2 as _cv2           # noqa: F401
        import torch as _torch       # noqa: F401
        import albumentations as _A  # noqa: F401
    except Exception:
        pass
