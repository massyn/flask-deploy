import os
from datetime import timedelta

_database_url = os.environ.get('DATABASE_URL', '')
if not _database_url:
    raise RuntimeError(
        'DATABASE_URL is required — set it in your .env file. No default is provided.'
    )


class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY', 'dev-secret-please-change')
    DATABASE_URL = _database_url
    GOOGLE_CLIENT_ID = os.environ.get('GOOGLE_CLIENT_ID', '')
    GOOGLE_CLIENT_SECRET = os.environ.get('GOOGLE_CLIENT_SECRET', '')
    TEST_USER = os.environ.get('TEST_USER', '')
    PERMANENT_SESSION_LIFETIME = timedelta(days=30)
    FORCE_HTTPS = os.environ.get('FORCE_HTTPS', 'false').lower() == 'true'
    SESSION_COOKIE_SECURE = os.environ.get('FLASK_DEBUG', 'False').lower() != 'true'
    VERSION = os.environ.get('VERSION', '')
    GTAG_ID = os.environ.get('GTAG_ID', '')
