import os
from pathlib import Path
from dotenv import load_dotenv

_env_file = Path('.env_dev') if Path('.env_dev').exists() else Path('.env')
load_dotenv(_env_file)

from app import create_app  # noqa: E402 — must load env before importing config

app = create_app()

if __name__ == '__main__':
    app.run(
        host=os.environ.get('FLASK_HOST', '0.0.0.0'),
        port=int(os.environ.get('FLASK_PORT', 5000)),
        debug=os.environ.get('FLASK_DEBUG', 'False').lower() == 'true',
    )
