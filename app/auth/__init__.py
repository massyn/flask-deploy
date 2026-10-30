from flask import Blueprint, redirect, render_template, url_for, session, current_app
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
    if session.get('user'):
        return redirect(url_for('main.index'))
    return render_template('login.html')


@bp.route('/google')
def google():
    test_user = current_app.config.get('TEST_USER', '')
    if test_user:
        return redirect(url_for('auth.test_callback'))
    from app.auth.service import get_oauth_redirect_uri
    return oauth.google.authorize_redirect(get_oauth_redirect_uri())


@bp.route('/callback')
def callback():
    token = oauth.google.authorize_access_token()
    info = token.get('userinfo', {})
    from app.auth.service import find_or_create_user
    establish_session(find_or_create_user(info['sub'], info.get('name', ''), info.get('email', '')))
    return redirect(after_login_url())


@bp.route('/test-callback')
def test_callback():
    test_user = current_app.config.get('TEST_USER', '')
    if not test_user:
        return redirect(url_for('auth.login'))
    from app.auth.service import find_or_create_user
    establish_session(find_or_create_user(f'test:{test_user}', test_user, ''))
    return redirect(after_login_url())


@bp.route('/logout')
def logout():
    session.pop('user', None)
    return redirect(url_for('main.index'))


def establish_session(user: dict) -> None:
    """Start the user's session once a sign-in method has proven who they are."""
    session.permanent = True
    session['user'] = {
        'id': user['id'],
        'name': user['name'],
        'email': user.get('email', ''),
    }


def after_login_url() -> str:
    return url_for('main.index')


from app.auth import passkey_routes  # noqa: E402,F401 - registers the passkey routes on bp
