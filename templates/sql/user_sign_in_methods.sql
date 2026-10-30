SELECT u.google_id, COUNT(p.id) AS passkeys
FROM users u
LEFT JOIN passkeys p ON p.user_id = u.id
WHERE u.id = {% if dialect == 'sqlite' %}?{% else %}%s{% endif %}
GROUP BY u.id, u.google_id
