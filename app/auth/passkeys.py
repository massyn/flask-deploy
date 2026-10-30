"""Passkeys (WebAuthn): creating them, and signing in with one.

Each ceremony has two steps. The server sends options with a fresh challenge, the browser asks the
user's device to create or use a passkey, and the server verifies what comes back. The challenge
waits in the session between the two steps and is used once.
"""

import json
import logging

from flask import current_app, request, session
from webauthn import (
    generate_authentication_options,
    generate_registration_options,
    options_to_json,
    verify_authentication_response,
    verify_registration_response,
)
from webauthn.helpers import base64url_to_bytes, bytes_to_base64url
from webauthn.helpers.exceptions import WebAuthnException
from webauthn.helpers.structs import (
    AuthenticatorSelectionCriteria,
    PublicKeyCredentialDescriptor,
    ResidentKeyRequirement,
    UserVerificationRequirement,
)

from app.auth.service import new_passkey_handle
from app.db import execute, execute_batch, query

log = logging.getLogger(__name__)

NAME_MAX_LENGTH = 60


class PasskeyError(Exception):
    """A passkey could not be created or used; the message is safe to show the user."""


def _relying_party() -> tuple[str, list[str]]:
    """The domain passkeys belong to, and the page origins allowed to use them."""
    hosts = current_app.config.get('APP_HOSTNAMES') or []
    if hosts:
        rp_id = current_app.config.get('PASSKEY_RP_ID') or hosts[0]
        return rp_id, [f'https://{host}' for host in hosts]
    # Development, with no hostnames configured: the host the page was loaded from.
    rp_id = current_app.config.get('PASSKEY_RP_ID') or request.host.split(':')[0]
    return rp_id, [request.host_url.rstrip('/')]


def registration_options(user_id: int | None, name: str) -> str:
    """Options for creating a passkey, as JSON: for a signed-in user, or a new one known by name."""
    rp_id, _ = _relying_party()
    if user_id is None:
        handle, existing = new_passkey_handle(), []
    else:
        handle = query('user_passkey_handle.sql', (user_id,))[0]['passkey_handle']
        existing = list_passkeys(user_id)
    options = generate_registration_options(
        rp_id=rp_id,
        rp_name=current_app.config['PASSKEY_RP_NAME'],
        user_id=base64url_to_bytes(handle),
        user_name=name,
        user_display_name=name,
        # Discoverable, so the user can sign in without typing anything first.
        authenticator_selection=AuthenticatorSelectionCriteria(
            resident_key=ResidentKeyRequirement.REQUIRED,
            user_verification=UserVerificationRequirement.PREFERRED,
        ),
        exclude_credentials=[
            PublicKeyCredentialDescriptor(id=base64url_to_bytes(row['credential_id']))
            for row in existing
        ],
    )
    session['passkey_registration'] = {
        'challenge': bytes_to_base64url(options.challenge),
        'handle': handle,
        'name': name,
        'is_new_user': user_id is None,
    }
    return options_to_json(options)


def register(credential: dict) -> tuple[dict, bool]:
    """Verify a new passkey and store it, creating the user if they are new.

    Returns the user and whether they were created.
    """
    pending = session.pop('passkey_registration', None)
    if pending is None:
        raise PasskeyError('That took too long. Please try again.')
    rp_id, origins = _relying_party()
    try:
        verified = verify_registration_response(
            credential=credential,
            expected_challenge=base64url_to_bytes(pending['challenge']),
            expected_rp_id=rp_id,
            expected_origin=origins,
        )
    except WebAuthnException as e:
        log.warning('Passkey registration rejected: %s', e)
        raise PasskeyError("That passkey couldn't be created. Please try again.") from e

    statements = []
    if pending['is_new_user']:
        # No Google account: the passkey is the only way this user signs in.
        statements.append(('user_insert.sql', (None, pending['name'], None, pending['handle'])))
    statements.append(
        (
            'passkey_insert.sql',
            (
                bytes_to_base64url(verified.credential_id),
                bytes_to_base64url(verified.credential_public_key),
                verified.sign_count,
                pending['handle'],
            ),
        )
    )
    execute_batch(statements)
    user = query('user_by_passkey_handle.sql', (pending['handle'],))[0]
    log.info('Passkey added for user %s', user['id'])
    return user, pending['is_new_user']


def authentication_options() -> str:
    """Options for signing in with any passkey the user's device holds, as JSON."""
    rp_id, _ = _relying_party()
    options = generate_authentication_options(
        rp_id=rp_id, user_verification=UserVerificationRequirement.PREFERRED
    )
    session['passkey_authentication'] = bytes_to_base64url(options.challenge)
    return options_to_json(options)


def authenticate(credential: dict) -> dict:
    """Verify a passkey sign-in and return the user."""
    challenge = session.pop('passkey_authentication', None)
    if challenge is None:
        raise PasskeyError('That took too long. Please try again.')
    rows = query('passkey_by_credential.sql', (credential.get('id', ''),))
    if not rows:
        raise PasskeyError("That passkey isn't recognised.")
    passkey = rows[0]

    # The device names the user the passkey was made for; it must be the one we stored.
    user_handle = (credential.get('response') or {}).get('userHandle')
    if user_handle and base64url_to_bytes(user_handle) != base64url_to_bytes(
        passkey['passkey_handle']
    ):
        log.warning('Passkey %s presented for another user', passkey['id'])
        raise PasskeyError("That passkey isn't recognised.")

    rp_id, origins = _relying_party()
    try:
        verified = verify_authentication_response(
            credential=credential,
            expected_challenge=base64url_to_bytes(challenge),
            expected_rp_id=rp_id,
            expected_origin=origins,
            credential_public_key=base64url_to_bytes(passkey['public_key']),
            credential_current_sign_count=passkey['sign_count'],
        )
    except WebAuthnException as e:
        log.warning('Passkey sign-in rejected for passkey %s: %s', passkey['id'], e)
        raise PasskeyError("That passkey couldn't be verified. Please try again.") from e

    execute('passkey_record_use.sql', (verified.new_sign_count, passkey['id']))
    return query('user_by_id.sql', (passkey['user_id'],))[0]


def list_passkeys(user_id: int) -> list[dict]:
    return query('passkey_list_by_user.sql', (user_id,))


def delete_passkey(user_id: int, passkey_id: int) -> None:
    """Remove one of the user's passkeys, unless it is their only way to sign in."""
    account = query('user_sign_in_methods.sql', (user_id,))[0]
    if not account['google_id'] and account['passkeys'] <= 1:
        raise PasskeyError(
            'This is your only passkey, so removing it would lock you out. Add another first.'
        )
    execute('passkey_delete.sql', (passkey_id, user_id))
    log.info('Passkey %s removed by user %s', passkey_id, user_id)


def parse_credential(raw: bytes) -> dict:
    """The credential the browser posted, as a dict."""
    try:
        credential = json.loads(raw)
    except ValueError as e:
        raise PasskeyError('Your browser sent an unreadable passkey.') from e
    if not isinstance(credential, dict):
        raise PasskeyError('Your browser sent an unreadable passkey.')
    return credential
