from flask import request, url_for, current_app
from app.db import query, execute


def get_remote_ip() -> str:
    return (
        request.headers.get('CF-Connecting-IP')
        or request.headers.get('X-Real-IP')
        or request.remote_addr
        or ''
    )


def get_oauth_redirect_uri() -> str:
    cf_visitor = request.headers.get('CF-Visitor', '')
    if '"scheme":"https"' in cf_visitor:
        return url_for('auth.callback', _external=True, _scheme='https')
    if current_app.config.get('FORCE_HTTPS'):
        return url_for('auth.callback', _external=True, _scheme='https')
    return url_for('auth.callback', _external=True)


def find_or_create_user(google_id: str, name: str, email: str) -> dict:
    rows = query('user_by_google_id.sql', (google_id,))
    if rows:
        return rows[0]
    execute('user_insert.sql', (google_id, name, email))
    return query('user_by_google_id.sql', (google_id,))[0]
