SELECT id, credential_id, created_on, last_used
FROM passkeys
WHERE user_id = {% if dialect == 'sqlite' %}?{% else %}%s{% endif %}
ORDER BY created_on, id
