"""
PurePick — Base Settings
Shared across all environments. Never import directly in production;
use settings.dev or settings.prod instead.
"""
import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent.parent.parent  # → backend/

# ── Security ────────────────────────────────────────────────────────────────
SECRET_KEY = os.environ['SECRET_KEY']   # Hard fail if missing — intentional

# ── Apps ────────────────────────────────────────────────────────────────────
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'rest_framework_simplejwt',
    'rest_framework_simplejwt.token_blacklist',
    'corsheaders',
    'purepick_core',
    'scanner',
    'skin_analysis',
]

# ── Middleware ───────────────────────────────────────────────────────────────
MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'purepick_core.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'purepick_core.wsgi.application'

# ── Auth ─────────────────────────────────────────────────────────────────────
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator', 'OPTIONS': {'min_length': 8}},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

# ── JWT ──────────────────────────────────────────────────────────────────────
from datetime import timedelta

SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(hours=12),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=30),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'AUTH_HEADER_TYPES': ('Bearer',),
    'UPDATE_LAST_LOGIN': True,
}

# ── DRF ──────────────────────────────────────────────────────────────────────
REST_FRAMEWORK = {
    'DEFAULT_RENDERER_CLASSES': ['rest_framework.renderers.JSONRenderer'],
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
    'DEFAULT_THROTTLE_CLASSES': [
        'rest_framework.throttling.AnonRateThrottle',
        'rest_framework.throttling.UserRateThrottle',
    ],
    'DEFAULT_THROTTLE_RATES': {
        'anon': '20/hour',
        'user': '200/hour',
        'ai_endpoints': '30/hour',      # tighter limit for Gemini-backed endpoints
    },
}

# ── i18n ─────────────────────────────────────────────────────────────────────
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'                       # Store everything in UTC; localise in client
USE_I18N = True
USE_TZ = True

# ── Static / Media ────────────────────────────────────────────────────────────
STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# ── External AI ───────────────────────────────────────────────────────────────
GEMINI_API_KEY = os.getenv('GEMINI_API_KEY', '')

# ── Internal paths ────────────────────────────────────────────────────────────
PUREPICK_DB_PATH = BASE_DIR / 'datasets' / 'purepick_db.sqlite'
MODEL_PATH = BASE_DIR / 'scanner' / 'ingredient_safety_model.pkl'
VECTORIZER_PATH = BASE_DIR / 'scanner' / 'tfidf_vectorizer.pkl'

# ── Google OAuth ──────────────────────────────────────────────────────────────
GOOGLE_CLIENT_ID = os.getenv('GOOGLE_CLIENT_ID', '')   # Required for token verification

# ── Celery + Redis ────────────────────────────────────────────────────────────
_REDIS_URL = os.getenv('REDIS_URL', 'redis://localhost:6379/0')

CELERY_BROKER_URL = _REDIS_URL
CELERY_RESULT_BACKEND = _REDIS_URL
CELERY_ACCEPT_CONTENT = ['json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_TIMEZONE = 'UTC'
CELERY_TASK_TRACK_STARTED = True          # expose STARTED state to polling endpoint
CELERY_TASK_TIME_LIMIT = 300              # hard kill after 5 min (covers cold-start model load)
CELERY_TASK_SOFT_TIME_LIMIT = 270         # graceful cleanup at 4.5 min
CELERY_WORKER_PREFETCH_MULTIPLIER = 1     # don't prefetch — ML tasks are long
CELERY_TASK_ACKS_LATE = True              # ack only after completion — no lost tasks
CELERY_WORKER_MAX_TASKS_PER_CHILD = 50    # increased: model stays warm longer between respawns
CELERY_RESULT_EXPIRES = 3600              # keep results 1 hour

# Route heavy ML inference to dedicated queue
# Start workers:
#   celery -A purepick_core worker -Q ml --concurrency=2 --loglevel=info
#   celery -A purepick_core worker -Q default --concurrency=4 --loglevel=info
CELERY_TASK_ROUTES = {
    'scanner.tasks.run_ocr_and_analyze':       {'queue': 'ml'},
    'skin_analysis.tasks.run_skin_analysis':   {'queue': 'ml'},
    'scanner.tasks.call_gemini_chat':          {'queue': 'default'},
    'scanner.tasks.call_gemini_tips':          {'queue': 'default'},
    'scanner.tasks.run_barcode_analysis':      {'queue': 'default'},  # network I/O, not ml
}

# ── Email (password reset) ────────────────────────────────────────────────────
# Dev: prints to console. Prod: configure SMTP or SendGrid
# Email — set these in Railway environment variables:
#   EMAIL_HOST_USER     = your Gmail address (e.g. purepick.app@gmail.com)
#   EMAIL_HOST_PASSWORD = your Gmail App Password (16-char, not your login password)
#                         Generate at: myaccount.google.com → Security → App Passwords
#   DEFAULT_FROM_EMAIL  = same Gmail address
EMAIL_BACKEND       = 'django.core.mail.backends.smtp.EmailBackend'
EMAIL_HOST          = os.getenv('EMAIL_HOST', 'smtp.gmail.com')
EMAIL_PORT          = int(os.getenv('EMAIL_PORT', '587'))
EMAIL_USE_TLS       = True
EMAIL_HOST_USER     = os.getenv('EMAIL_HOST_USER', '')
EMAIL_HOST_PASSWORD = os.getenv('EMAIL_HOST_PASSWORD', '')
DEFAULT_FROM_EMAIL  = os.getenv('DEFAULT_FROM_EMAIL', os.getenv('EMAIL_HOST_USER', 'noreply@purepick.app'))

# Deep-link base URL for password reset links in emails
FRONTEND_BASE_URL = os.getenv('FRONTEND_BASE_URL', 'purepick://')

# ── Firebase Admin (FCM push notifications) ──────────────────────────────────
# Path to Firebase service account JSON (download from Firebase Console)
# Leave blank to disable push notifications
FIREBASE_CREDENTIALS_PATH = os.getenv('FIREBASE_CREDENTIALS_PATH', '')
