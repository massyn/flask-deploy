from flask import Blueprint, redirect, url_for, session, current_app
from authlib.integrations.flask_client import OAuth

bp = Blueprint('auth', __name__, url_prefix='/auth')
oauth = OAuth()

oauth.register(
    name='google',
    server_metadata_url='https://accounts.google.com/.well-known/openid-configuration',
    client_kwargs={'scope': 'openid email profile'},
)


@bp.route('/login')
def login():
    test_user = current_app.config.get('TEST_USER', '')
    if test_user:
        return redirect(url_for('auth.test_callback'))
    from app.auth.service import get_oauth_redirect_uri
    return oauth.google.authorize_redirect(get_oauth_redirect_uri())


@bp.route('/callback')
def callback():
    token = oauth.google.authorize_access_token()
    info = token.get('userinfo', {})
    _establish_session(
        google_id=info['sub'],
        name=info.get('name', ''),
        email=info.get('email', ''),
    )
    return redirect(url_for('main.index'))


@bp.route('/test-callback')
def test_callback():
    test_user = current_app.config.get('TEST_USER', '')
    if not test_user:
        return redirect(url_for('auth.login'))
    _establish_session(
        google_id=f'test:{test_user}',
        name=test_user,
        email='',
    )
    return redirect(url_for('main.index'))


@bp.route('/logout')
def logout():
    session.pop('user', None)
    return redirect(url_for('main.index'))


def _establish_session(google_id: str, name: str, email: str) -> None:
    from app.auth.service import find_or_create_user
    user = find_or_create_user(google_id, name, email)
    session.permanent = True
    session['user'] = {
        'id': user['id'],
        'name': user['name'],
        'email': user.get('email', ''),
    }
