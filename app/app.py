import os

import psycopg2
from flask import Flask, Response

app = Flask(__name__)


def get_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        dbname=os.getenv("POSTGRES_DB", "app"),
        user=os.getenv("POSTGRES_USER", "app"),
        password=os.getenv("POSTGRES_PASSWORD"),
        connect_timeout=3,
    )


@app.get("/health")
def health():
    return Response("ok\n", mimetype="text/plain")


@app.get("/")
def index():
    connection = get_connection()
    try:
        with connection, connection.cursor() as cursor:
            cursor.execute(
                "CREATE TABLE IF NOT EXISTS visits ("
                "id SERIAL PRIMARY KEY, visited_at TIMESTAMP DEFAULT now())"
            )
            cursor.execute("INSERT INTO visits DEFAULT VALUES")
            cursor.execute("SELECT count(*) FROM visits")
            count = cursor.fetchone()[0]
    finally:
        connection.close()

    return Response(f"Hello from Docker, Иващенко! Visits: {count}\n", mimetype="text/plain")
