"""
PurePick — Production Settings
Run with: DJANGO_SETTINGS_MODULE=purepick_core.settings.prod

Required env vars (all must be set or startup fails):
  SECRET_KEY, DATABASE_URL, REDIS_URL,
  GEMINI_API_KEY, GOOGLE_CLIENT_ID, ALLOWED_HOSTS_CSV
"""
from .base import *  # noqa: F401, F403
import os
import dj_database_url

DEBUG = False

# ── Hosts — comma-separated list in env var ───────────────────────────────────
_hosts_csv = os.environ.get('ALLOWED_HOSTS_CSV', '')
if not _hosts_csv:
    ALLOWED_HOSTS = ['*']
else:
    ALLOWED_HOSTS = [h.strip() for h in _hosts_csv.split(',')]

# ── CSRF ──────────────────────────────────────────────────────────────────────
CSRF_TRUSTED_ORIGINS = [f"https://{h}" for h in ALLOWED_HOSTS if h != '*']

# ── Database ──────────────────────────────────────────────────────────────────
# Railway provides DATABASE_URL automatically if Postgres service is attached.
DATABASES = {
    'default': dj_database_url.config(
        default=os.environ.get('DATABASE_URL'),
        conn_max_age=60,
        conn_health_checks=True,
        ssl_require=True,
    )
}

# ── Redis & Celery ────────────────────────────────────────────────────────────
_redis_url = os.environ.get('REDIS_URL') or os.environ.get('REDISURL') or 'redis://localhost:6379/0'
CELERY_BROKER_URL = _redis_url
CELERY_RESULT_BACKEND = _redis_url
# Force immediate task execution visibility
CELERY_TASK_TRACK_STARTED = True
CELERY_TASK_ACKS_LATE = False

# ── Static Files (Whitenoise) ────────────────────────────────────────────────
STORAGES = {
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}

# ── CORS ──────────────────────────────────────────────────────────────────────
_cors_csv = os.getenv('CORS_ALLOWED_ORIGINS_CSV', '')
if _cors_csv:
    CORS_ALLOWED_ORIGINS = [o.strip() for o in _cors_csv.split(',') if o.strip()]
    CORS_ALLOW_ALL_ORIGINS = False
else:
    # For initial mobile testing, allow all or set your specific app origin
    CORS_ALLOW_ALL_ORIGINS = True

CORS_ALLOW_CREDENTIALS = True

# ── HTTPS security headers ────────────────────────────────────────────────────
SECURE_SSL_REDIRECT = False             # Railway handles HTTPS at the proxy level
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
SECURE_HSTS_SECONDS = 31536000          # 1 year
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
X_FRAME_OPTIONS = 'DENY'

# ── Logging — structured JSON for log aggregators ─────────────────────────────
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'json': {
            '()': 'pythonjsonlogger.jsonlogger.JsonFormatter',
            'format': '%(asctime)s %(levelname)s %(name)s %(message)s',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'json',
        },
    },
    'root': {'handlers': ['console'], 'level': 'WARNING'},
    'loggers': {
        'django': {'handlers': ['console'], 'level': 'WARNING', 'propagate': False},
        'django.security': {'handlers': ['console'], 'level': 'ERROR', 'propagate': False},
        'purepick_core': {'handlers': ['console'], 'level': 'INFO', 'propagate': False},
        'scanner': {'handlers': ['console'], 'level': 'INFO', 'propagate': False},
        'skin_analysis': {'handlers': ['console'], 'level': 'INFO', 'propagate': False},
    },
}
