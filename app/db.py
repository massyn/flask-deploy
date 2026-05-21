import os
import sqlite3
from flask import current_app, g
from jinja2 import Environment, FileSystemLoader


def _sql_env() -> Environment:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return Environment(loader=FileSystemLoader(os.path.join(root, 'templates', 'sql')))


def render_sql(template_name: str, dialect: str, **kwargs) -> str:
    return _sql_env().get_template(template_name).render(dialect=dialect, **kwargs)


def get_db() -> tuple:
    if 'db' not in g:
        db_url = current_app.config['DATABASE_URL']
        if db_url.startswith('sqlite'):
            path = db_url[len('sqlite:///'):]
            conn = sqlite3.connect(path)
            conn.row_factory = sqlite3.Row
            g.db = conn
            g.dialect = 'sqlite'
        else:
            import psycopg
            from psycopg.rows import dict_row
            g.db = psycopg.connect(db_url, row_factory=dict_row)
            g.dialect = 'postgres'
    return g.db, g.dialect


def close_db(e=None) -> None:
    db = g.pop('db', None)
    if db is not None:
        db.close()


def query(template_name: str, params: tuple = ()) -> list[dict]:
    conn, dialect = get_db()
    sql = render_sql(template_name, dialect)
    cur = conn.cursor()
    cur.execute(sql, params)
    return [dict(row) for row in cur.fetchall()]


def execute(template_name: str, params: tuple = ()) -> None:
    conn, dialect = get_db()
    sql = render_sql(template_name, dialect)
    conn.cursor().execute(sql, params)
    conn.commit()


def init_db(app) -> None:
    with app.app_context():
        conn, dialect = get_db()
        sql = render_sql('schema.sql', dialect)
        conn.cursor().execute(sql)
        conn.commit()
