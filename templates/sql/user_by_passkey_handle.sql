SELECT id, name, email, created_on
FROM users
WHERE passkey_handle = {% if dialect == 'sqlite' %}?{% else %}%s{% endif %}
