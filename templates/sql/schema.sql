CREATE TABLE IF NOT EXISTS users (
    {% if dialect == 'sqlite' %}
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    {% else %}
    id SERIAL PRIMARY KEY,
    {% endif %}
    google_id TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    email TEXT,
    created_on {% if dialect == 'sqlite' %}DATETIME{% else %}TIMESTAMP{% endif %} DEFAULT CURRENT_TIMESTAMP
)
