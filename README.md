# flask-deploy

A curl-able, self-contained bash script that deploys a Flask application to an Ubuntu/Debian server using Gunicorn, systemd, and Nginx. Idempotent — safe to run multiple times against the same slug.

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/<user>/flask-deploy/main/deploy.sh \
  | sudo bash -s -- --slug myapp --domain example.com --repo https://github.com/user/myapp
```

Or download and run directly:

```bash
sudo bash deploy.sh --slug myapp --domain example.com --repo https://github.com/user/myapp
```

## Parameters

| Flag | Required | Description |
|------|----------|-------------|
| `--slug` | Yes | App identifier — used for all directory and service naming |
| `--domain` | Yes | Nginx `server_name` value(s), space-separated |
| `--repo` | Yes | Git repository URL to clone |
| `--password` | No | Enable HTTP basic auth (username: `admin`, password: `<value>`) |
| `--cloudflare` | No | Flag — block all non-Cloudflare traffic using live IP ranges |
| `--dry-run` | No | Flag — validate the repository only, no server changes |

## Examples

Basic deployment:

```bash
sudo bash deploy.sh \
  --slug kickstand \
  --domain kickstand.example.com \
  --repo https://github.com/acme/kickstand
```

With HTTP basic auth:

```bash
sudo bash deploy.sh \
  --slug kickstand \
  --domain kickstand.example.com \
  --repo https://github.com/acme/kickstand \
  --password s3cr3tpassword
```

Behind Cloudflare (blocks all non-Cloudflare traffic):

```bash
sudo bash deploy.sh \
  --slug kickstand \
  --domain kickstand.example.com \
  --repo https://github.com/acme/kickstand \
  --cloudflare
```

Validate a repository without making any changes:

```bash
bash deploy.sh \
  --slug kickstand \
  --domain kickstand.example.com \
  --repo https://github.com/acme/kickstand \
  --dry-run
```

## Private repositories

Private GitHub repositories are supported by embedding a Personal Access Token (PAT) in the `--repo` URL:

```bash
sudo bash deploy.sh \
  --slug kickstand \
  --domain kickstand.example.com \
  --repo https://<token>@github.com/massyn/kickstand
```

The token is passed to `git clone` and stored in `/opt/<slug>/.git/config` on the server. Treat the server's `/opt/<slug>/` directory accordingly.

**GitHub Actions example**

Store the PAT as a repository secret (e.g. `DEPLOY_TOKEN`) and pass it at deploy time — never hardcode it in the workflow file:

```yaml
- name: Deploy
  run: |
    ssh user@server "sudo bash deploy.sh \
      --slug kickstand \
      --domain kickstand.example.com \
      --repo https://${{ secrets.DEPLOY_TOKEN }}@github.com/massyn/kickstand"
```

**Security note**

The PAT needs only the minimum required scope: **Contents: Read-only** (classic token: `repo` scope with read access, or a fine-grained token scoped to the specific repository with `Contents: Read-only`). Do not grant write access, workflow permissions, or organisation-level scopes.

## Directory conventions

| Path | Purpose |
|------|---------|
| `/opt/<slug>/` | Git clone of the repository — disposable, never back this up |
| `/data/<slug>/` | Stateful data — SQLite databases, `.env` files — **back this up** |
| `/var/log/<slug>/` | Logs — `access.log`, `error.log` (gunicorn), `nginx.access.log`, `nginx.error.log` |

The port Gunicorn binds to is an internal implementation detail assigned automatically (starting from 5000, incrementing by 1 per new app). It is bound to `127.0.0.1` only and never exposed directly.

## Dry-run output

```
[✓] run.py found
[✓] requirements.txt found
[✓] gunicorn in requirements.txt
[✓] app object found in run.py
[!] .env missing
[!] DATABASE_URL not pointing to /data/kickstand/ — if your db gets hosed on redeploy, you had fair warning
```

`[✗]` items cause a non-zero exit. `[!]` items are warnings that do not block the run.

## Flask app contract

The deploy script expects the following in the root of the cloned repository.

### Required files

#### `run.py`

Must be present at the repository root. Must expose a module-level variable named `app`:

```python
app = Flask(__name__)
```

Gunicorn is invoked as `gunicorn run:app` — the filename and variable name are fixed.

Include an `if __name__ == '__main__'` block for local development:

```python
if __name__ == '__main__':
    app.run(
        host=os.environ.get('FLASK_HOST', '0.0.0.0'),
        port=int(os.environ.get('FLASK_PORT', 5000)),
        debug=os.environ.get('FLASK_DEBUG', 'False').lower() == 'true'
    )
```

#### `requirements.txt`

Must be at the repository root. Must list `gunicorn`.

### Recommended files

#### `.env`

Place secrets and environment-specific config here. The deploy script warns if it is absent.

If your app uses a SQLite database, point `DATABASE_URL` at `/data/<slug>/` so it survives redeployment:

```
DATABASE_URL=sqlite:////data/kickstand/app.db
SECRET_KEY=your-secret-key-here
```

The `/data/<slug>/` directory is created by the deploy script and is never wiped on redeploy.

Do not commit `.env` to the repository.

### Files generated by deploy.sh

These are written into `/opt/<slug>/` on every deploy. Do not commit them:

| File | Description |
|------|-------------|
| `gunicorn_config.py` | Gunicorn settings — overwritten on each run |
| `venv/` | Python virtual environment — rebuilt if missing |

Add both to `.gitignore`.

### Recommended project layout

```
my-app/
├── run.py              # Entry point — exposes `app`
├── requirements.txt    # Must include gunicorn
├── .env                # Secrets — do not commit
├── .gitignore          # Exclude venv/, gunicorn_config.py, .env
├── static/             # Static assets (optional)
└── templates/          # Jinja2 HTML templates
    └── base.html       # Base layout — all pages extend this
```

### Templates and routes

- All HTML via Jinja2 templates — never build HTML strings in Python.
- Use template inheritance: `base.html` defines layout; all pages extend it.
- Use Bootstrap 5 (CDN) for styling.
- Route handlers are thin: validate input, call service functions, return `render_template()`.
- Use `url_for()` for all internal links — never hardcode paths.

## Local development

```bash
python -m venv venv
source venv/bin/activate   # Linux/macOS
venv\Scripts\activate      # Windows
pip install -r requirements.txt
python ./run.py
```

The app runs at `http://localhost:5000` via Flask's development server. Gunicorn is used in production only.

## Prerequisites

- Ubuntu or Debian
- `sudo` access for systemd and Nginx configuration
- `git` available on the server (for clone/pull)

The script installs `nginx`, `python3-venv`, and (when `--password` is used) `apache2-utils` if they are not already present. It checks before installing and does not run `apt-get` unnecessarily.
