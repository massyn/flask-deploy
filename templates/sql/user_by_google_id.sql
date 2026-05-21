SELECT id, google_id, name, email, created_on
FROM users
WHERE google_id = {% if dialect == 'sqlite' %}?{% else %}%s{% endif %}
