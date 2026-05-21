INSERT INTO users (google_id, name, email)
VALUES ({% if dialect == 'sqlite' %}?, ?, ?{% else %}%s, %s, %s{% endif %})
