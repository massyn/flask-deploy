DELETE FROM passkeys
WHERE id = {% if dialect == 'sqlite' %}?{% else %}%s{% endif %}
AND user_id = {% if dialect == 'sqlite' %}?{% else %}%s{% endif %}
