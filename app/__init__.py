import os
from flask import Flask, render_template
from flask_wtf.csrf import CSRFProtect
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from config import Config

csrf = CSRFProtect()
limiter = Limiter(
    key_func=get_remote_address,
    default_limits=['200 per day', '50 per hour'],
    storage_uri='memory://',
)


def create_app() -> Flask:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    app = Flask(
        __name__,
        template_folder=os.path.join(root, 'templates'),
        static_folder=os.path.join(root, 'static'),
    )
    app.config.from_object(Config)

    csrf.init_app(app)
    limiter.init_app(app)

    from app.auth import oauth, bp as auth_bp
    oauth.init_app(app)
    app.register_blueprint(auth_bp)

    from app.main import bp as main_bp
    app.register_blueprint(main_bp)

    from app.db import close_db, init_db
    app.teardown_appcontext(close_db)
    init_db(app)

    @app.context_processor
    def inject_version():
        return dict(version=app.config.get('VERSION', ''))

    @app.errorhandler(404)
    def not_found(e):
        return render_template('error.html', error_code=404, error_message='Page not found.'), 404

    @app.errorhandler(500)
    def server_error(e):
        return render_template('error.html', error_code=500, error_message='Internal server error.'), 500

    @app.errorhandler(429)
    def ratelimit_handler(e):
        return render_template('error.html', error_code=429, error_message='Rate limit exceeded. Please try again later.'), 429

    return app
