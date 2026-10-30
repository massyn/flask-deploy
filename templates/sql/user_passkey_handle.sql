SELECT passkey_handle
FROM users
WHERE id = {% if dialect == 'sqlite' %}?{% else %}%s{% endif %}
