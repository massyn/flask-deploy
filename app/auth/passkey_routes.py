"""Passkey sign-up, sign-in and management. The page script in static/js/passkeys.js drives these."""

from flask import Response, flash, jsonify, redirect, render_template, request, session, url_for

from app.auth import after_login_url, bp, establish_session, passkeys
from app.auth.decorators import login_required


def _options(options_json: str) -> Response:
    return Response(options_json, mimetype='application/json')


def _refused(error: passkeys.PasskeyError):
    return jsonify(error=str(error)), 400


@bp.route('/passkey/signup')
def passkey_signup():
    if session.get('user'):
        return redirect(url_for('auth.passkey_list'))
    return render_template('passkey_signup.html', name_max_length=passkeys.NAME_MAX_LENGTH)


@bp.route('/passkey/register/options', methods=['POST'])
def passkey_register_options():
    # Signed in: add a passkey to this account. Signed out: a new user, known only by name.
    user = session.get('user')
    if user:
        return _options(passkeys.registration_options(user['id'], user['name'] or 'User'))
    name = str((request.get_json(silent=True) or {}).get('name', '')).strip()
    if not name or len(name) > passkeys.NAME_MAX_LENGTH:
        return jsonify(error='Please enter your name.'), 400
    return _options(passkeys.registration_options(None, name))


@bp.route('/passkey/register', methods=['POST'])
def passkey_register():
    try:
        user, is_new_user = passkeys.register(passkeys.parse_credential(request.get_data()))
    except passkeys.PasskeyError as e:
        return _refused(e)
    if is_new_user:
        establish_session(user)
        return jsonify(redirect=after_login_url())
    flash('Passkey added. You can sign in with it from now on.', 'success')
    return jsonify(redirect=url_for('auth.passkey_list'))


@bp.route('/passkey/login/options', methods=['POST'])
def passkey_login_options():
    return _options(passkeys.authentication_options())


@bp.route('/passkey/login', methods=['POST'])
def passkey_login():
    try:
        user = passkeys.authenticate(passkeys.parse_credential(request.get_data()))
    except passkeys.PasskeyError as e:
        return _refused(e)
    establish_session(user)
    return jsonify(redirect=after_login_url())


@bp.route('/passkeys')
@login_required
def passkey_list():
    return render_template('passkeys.html', passkeys=passkeys.list_passkeys(session['user']['id']))


@bp.route('/passkey/<int:passkey_id>/delete', methods=['POST'])
@login_required
def passkey_delete(passkey_id: int):
    try:
        passkeys.delete_passkey(session['user']['id'], passkey_id)
    except passkeys.PasskeyError as e:
        flash(str(e), 'danger')
    else:
        flash('Passkey removed.', 'info')
    return redirect(url_for('auth.passkey_list'))
