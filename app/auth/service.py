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
    is_https = '"scheme":"https"' in cf_visitor or current_app.config.get('FORCE_HTTPS')
    scheme = 'https' if is_https else request.scheme

    trusted_hostnames = current_app.config.get('APP_HOSTNAMES', [])
    if trusted_hostnames:
        # request.host is attacker-controllable via the Host header, so only use it
        # if it matches an entry in the trusted allow-list; otherwise fall back to
        # the first configured hostname.
        hostname = request.host if request.host in trusted_hostnames else trusted_hostnames[0]
        return f'{scheme}://{hostname}{url_for("auth.callback")}'

    # No trusted hostnames configured — falls back to request.host, which is
    # attacker-controllable via the Host header. Set APP_HOSTNAME in production.
    return url_for('auth.callback', _external=True, _scheme=scheme)


def find_or_create_user(google_id: str, name: str, email: str) -> dict:
    rows = query('user_by_google_id.sql', (google_id,))
    if rows:
        return rows[0]
    execute('user_insert.sql', (google_id, name, email))
    return query('user_by_google_id.sql', (google_id,))[0]
