# Flask Hello World

A production-ready Flask application with built-in security features including CSRF protection, rate limiting, and modern Bootstrap 5 UI.

## Features

- **CSRF Protection**: Flask-WTF for cross-site request forgery protection
- **Rate Limiting**: Flask-Limiter to prevent abuse
- **Environment Configuration**: Secure configuration with python-dotenv
- **Modern UI**: Bootstrap 5 responsive design with modern color schemes
- **Production Ready**: Configured for Gunicorn deployment
- **Security**: Latest stable and secure versions of all dependencies

## Project Structure

```
flask-deploy/
├── src/
│   ├── run.py                 # Main Flask application
│   ├── requirements.txt       # Python dependencies
│   └── templates/            # Jinja2 templates
│       ├── base.html         # Base template with Bootstrap 5
│       ├── index.html        # Home page
│       ├── about.html        # About page
│       └── error.html        # Error page
├── templates/                # Deployment templates
│   ├── gunicorn_config.py   # Gunicorn configuration
│   ├── nginx.conf           # Nginx configuration
│   └── systemd.j2           # Systemd service template
├── .env                     # Environment variables (DO NOT COMMIT)
├── deploy.sh                # Deployment script
└── README.md                # This file
```

## Installation

### Development Setup (Windows)

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd flask-deploy
   ```

2. **Create a virtual environment**
   ```bash
   cd src
   python -m venv venv
   venv\Scripts\activate
   ```

3. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

4. **Configure environment variables**
   - Edit `.env` file in the project root
   - Generate a secure SECRET_KEY:
     ```bash
     python -c "import secrets; print(secrets.token_hex(32))"
     ```
   - Update the `.env` file with your secret key

5. **Run the development server**
   ```bash
   python run.py
   ```

6. **Access the application**
   - Open your browser to `http://localhost:5000`

### Production Deployment (Linux)

1. **Run the deployment script**
   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

   The script will:
   - Detect your OS (Ubuntu or Amazon Linux)
   - Install nginx if not present
   - Install Python3 if not present
   - Set up the application for production

2. **Configure Gunicorn**
   - Copy `templates/gunicorn_config.py` to `src/gunicorn_config.py`
   - Update the port and process name in the configuration

3. **Start with Gunicorn**
   ```bash
   cd src
   gunicorn -c gunicorn_config.py run:app
   ```

## Configuration

### Environment Variables (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| SECRET_KEY | Secret key for Flask sessions and CSRF | dev-secret-key-change-in-production |
| FLASK_HOST | Development server host | 0.0.0.0 |
| FLASK_PORT | Development server port | 5000 |
| FLASK_DEBUG | Enable debug mode | True |

**IMPORTANT**: Always change `SECRET_KEY` in production!

### Rate Limiting

Default rate limits:
- Global: 200 requests per day, 50 requests per hour
- Per route: 30 requests per minute

Configure in `src/run.py` by modifying the `@limiter.limit()` decorators.

## Security Features

1. **CSRF Protection**
   - All forms automatically include CSRF tokens
   - Tokens validated on form submission
   - Configure timeout with `WTF_CSRF_TIME_LIMIT`

2. **Rate Limiting**
   - Prevents API abuse and DDoS attacks
   - IP-based limiting
   - Customizable per route

3. **Environment-based Configuration**
   - Sensitive data in `.env` file
   - Never commit `.env` to version control
   - Add `.env` to `.gitignore`

## Development

### Running in Development Mode

```bash
cd src
python run.py
```

The application will run on `http://localhost:5000` with debug mode enabled.

### Running in Production Mode

```bash
cd src
gunicorn -c gunicorn_config.py run:app
```

## Technology Stack

- **Backend**: Flask 3.1.0
- **WSGI Server**: Gunicorn 23.0.0
- **CSRF Protection**: Flask-WTF 1.2.2
- **Rate Limiting**: Flask-Limiter 3.8.0
- **Configuration**: python-dotenv 1.0.1
- **Frontend**: Bootstrap 5.3.3
- **Template Engine**: Jinja2

## License

This project is provided as-is for educational and development purposes.
