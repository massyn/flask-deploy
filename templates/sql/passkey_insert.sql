INSERT INTO passkeys (user_id, credential_id, public_key, sign_count)
SELECT id, {% if dialect == 'sqlite' %}?, ?, ?{% else %}%s, %s, %s{% endif %}
FROM users
WHERE passkey_handle = {% if dialect == 'sqlite' %}?{% else %}%s{% endif %}
