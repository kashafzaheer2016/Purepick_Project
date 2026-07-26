"""
PurePick — Development Settings
Run with: DJANGO_SETTINGS_MODULE=purepick_core.settings.dev
"""
from .base import *  # noqa: F401, F403

DEBUG = True

ALLOWED_HOSTS = ['*']

# ── Database — local PostgreSQL ───────────────────────────────────────────────
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.getenv('DB_NAME', 'purepick_db'),
        'USER': os.getenv('DB_USER', 'postgres'),
        'PASSWORD': os.getenv('DB_PASSWORD', ''),
        'HOST': os.getenv('DB_HOST', 'localhost'),
        'PORT': os.getenv('DB_PORT', '5432'),
    }
}

# ── CORS — allow Flutter dev emulator ────────────────────────────────────────
CORS_ALLOWED_ORIGINS = [
    'http://localhost:8080',
    'http://127.0.0.1:8080',
    'http://192.168.1.2:8080',
]
CORS_ALLOW_ALL_ORIGINS = True

# ── Relaxed JWT for dev ───────────────────────────────────────────────────────
from datetime import timedelta
SIMPLE_JWT = {
    **SIMPLE_JWT,                       # noqa: F405 — inherited from base
    'ACCESS_TOKEN_LIFETIME': timedelta(days=7),   # longer in dev for convenience
}

# ── Logging — verbose in dev ──────────────────────────────────────────────────
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {
        'console': {'class': 'logging.StreamHandler'},
    },
    'root': {
        'handlers': ['console'],
        'level': 'DEBUG',
    },
    'loggers': {
        'django': {'handlers': ['console'], 'level': 'INFO', 'propagate': False},
        'purepick_core': {'handlers': ['console'], 'level': 'DEBUG', 'propagate': False},
        'scanner': {'handlers': ['console'], 'level': 'DEBUG', 'propagate': False},
        'skin_analysis': {'handlers': ['console'], 'level': 'DEBUG', 'propagate': False},
    },
}
