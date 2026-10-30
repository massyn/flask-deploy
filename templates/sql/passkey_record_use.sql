UPDATE passkeys
SET sign_count = {% if dialect == 'sqlite' %}?{% else %}%s{% endif %}, last_used = CURRENT_TIMESTAMP
WHERE id = {% if dialect == 'sqlite' %}?{% else %}%s{% endif %}
