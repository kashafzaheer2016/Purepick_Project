"""
purepick_core/settings/test.py
================================
Test-specific settings.
  - SQLite in-memory (fast, no Postgres needed in CI)
  - No Celery (tasks run synchronously via CELERY_TASK_ALWAYS_EAGER)
  - Dummy email backend
  - No real Gemini or Redis calls
"""
from .base import *  # noqa: F401, F403
import os

DEBUG = False
SECRET_KEY = 'test-secret-key-not-for-production'

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': ':memory:',
    }
}

# Run Celery tasks synchronously in tests
CELERY_TASK_ALWAYS_EAGER = True
CELERY_TASK_EAGER_PROPAGATES = True

# Never call real external services in tests
GEMINI_API_KEY = 'test-fake-gemini-key'
GOOGLE_CLIENT_ID = 'test-fake-google-client-id'
REDIS_URL = 'redis://localhost:6379/15'   # DB 15 = test isolation

# Email: capture in memory for assertion
EMAIL_BACKEND = 'django.core.mail.backends.locmem.EmailBackend'
DEFAULT_FROM_EMAIL = 'test@purepick.app'
FRONTEND_BASE_URL = 'purepick-test://'

# Disable password hashers for speed in tests (argon2 is intentionally slow)
PASSWORD_HASHERS = ['django.contrib.auth.hashers.MD5PasswordHasher']

# Use fast logging in tests
LOGGING = {
    'version': 1,
    'disable_existing_loggers': True,
    'handlers': {'null': {'class': 'logging.NullHandler'}},
    'root': {'handlers': ['null']},
}
