INSERT INTO users (google_id, name, email, passkey_handle)
VALUES ({% if dialect == 'sqlite' %}?, ?, ?, ?{% else %}%s, %s, %s, %s{% endif %})
