SELECT id, name, email, created_on
FROM users
WHERE id = {% if dialect == 'sqlite' %}?{% else %}%s{% endif %}
