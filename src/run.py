"""
Flask Hello World Application with Security Features

This is a production-ready Flask application with:
- CSRF protection
- Rate limiting
- Environment-based configuration
- Bootstrap 5 UI
"""
import os
from flask import Flask, render_template
from flask_wtf.csrf import CSRFProtect
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Initialize Flask app
app = Flask(__name__)

# Configuration
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-production')
app.config['WTF_CSRF_TIME_LIMIT'] = None  # CSRF tokens don't expire

# Initialize CSRF protection
csrf = CSRFProtect(app)

# Initialize rate limiter
limiter = Limiter(
    app=app,
    key_func=get_remote_address,
    default_limits=["200 per day", "50 per hour"],
    storage_uri="memory://"
)

@app.route('/')
@limiter.limit("30 per minute")
def index():
    """Home page route."""
    return render_template('index.html')

@app.route('/about')
@limiter.limit("30 per minute")
def about():
    """About page route."""
    return render_template('about.html')

@app.errorhandler(429)
def ratelimit_handler(e):
    """Handle rate limit exceeded."""
    return render_template('error.html',
                         error_code=429,
                         error_message="Rate limit exceeded. Please try again later."), 429

@app.errorhandler(404)
def not_found_handler(e):
    """Handle 404 errors."""
    return render_template('error.html',
                         error_code=404,
                         error_message="Page not found."), 404

@app.errorhandler(500)
def server_error_handler(e):
    """Handle 500 errors."""
    return render_template('error.html',
                         error_code=500,
                         error_message="Internal server error."), 500

if __name__ == '__main__':
    # This is only used for development
    # In production, use gunicorn
    app.run(
        host=os.environ.get('FLASK_HOST', '0.0.0.0'),
        port=int(os.environ.get('FLASK_PORT', 5000)),
        debug=os.environ.get('FLASK_DEBUG', 'False').lower() == 'true'
    )
