SELECT p.id, p.user_id, p.public_key, p.sign_count, u.passkey_handle
FROM passkeys p
JOIN users u ON u.id = p.user_id
WHERE p.credential_id = {% if dialect == 'sqlite' %}?{% else %}%s{% endif %}
