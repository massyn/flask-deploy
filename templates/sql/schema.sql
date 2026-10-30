CREATE TABLE IF NOT EXISTS users (
    {% if dialect == 'sqlite' %}
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    {% else %}
    id SERIAL PRIMARY KEY,
    {% endif %}
    -- NULL for users who signed up with a passkey alone.
    google_id TEXT UNIQUE,
    name TEXT NOT NULL,
    email TEXT,
    -- WebAuthn user handle (base64url): names the user on their passkeys without revealing the id.
    passkey_handle TEXT UNIQUE NOT NULL,
    created_on {% if dialect == 'sqlite' %}DATETIME{% else %}TIMESTAMP{% endif %} DEFAULT CURRENT_TIMESTAMP
);

-- A user's passkeys (WebAuthn credentials). Only the public key is stored: the private key stays on
-- the user's device or in their password manager.
CREATE TABLE IF NOT EXISTS passkeys (
    {% if dialect == 'sqlite' %}
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    {% else %}
    id SERIAL PRIMARY KEY,
    {% endif %}
    user_id INTEGER NOT NULL REFERENCES users(id),
    credential_id TEXT UNIQUE NOT NULL,  -- base64url
    public_key TEXT NOT NULL,            -- base64url COSE key
    sign_count BIGINT NOT NULL DEFAULT 0,
    created_on {% if dialect == 'sqlite' %}DATETIME{% else %}TIMESTAMP{% endif %} DEFAULT CURRENT_TIMESTAMP,
    last_used {% if dialect == 'sqlite' %}DATETIME{% else %}TIMESTAMP{% endif %}
);

CREATE INDEX IF NOT EXISTS idx_passkeys_user_id ON passkeys (user_id);
