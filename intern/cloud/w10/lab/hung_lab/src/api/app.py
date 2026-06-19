# Lab 2 buổi chiều: Flask app với /metrics và đọc DB secret
import os
import random
from flask import Flask, jsonify
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
PrometheusMetrics(app)  # Tự thêm /metrics

ERROR_RATE = float(os.getenv("ERROR_RATE", "0"))
VERSION = os.getenv("VERSION", "v1")
DB_PASSWORD_PATH = os.getenv("DB_PASSWORD_PATH", "/secrets/password")

def get_db_password():
    """Đọc DB password từ file được mount vào container"""
    try:
        with open(DB_PASSWORD_PATH, 'r') as f:
            return f.read().strip()
    except FileNotFoundError:
        return "SECRET_NOT_FOUND"
    except Exception as e:
        return f"ERROR: {str(e)}"

@app.get("/")
def index():
    if random.random() < ERROR_RATE:
        return jsonify(error="injected", version=VERSION), 500
    
    db_password = get_db_password()
    db_status = "connected" if db_password != "SECRET_NOT_FOUND" else "disconnected"
    
    return jsonify(
        ok=True,
        version=VERSION,
        db_status=db_status,
        db_password_loaded=db_password != "SECRET_NOT_FOUND"
    )

@app.get("/healthz")
def healthz():
    return "ok", 200

@app.get("/db-secret")
def db_secret():
    """Debug endpoint kiểm tra trạng thái secret"""
    password = get_db_password()
    return jsonify(
        password_path=DB_PASSWORD_PATH,
        password_found=password != "SECRET_NOT_FOUND",
        password_preview=password[:5] + "..." if len(password) > 5 else password
    )

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
