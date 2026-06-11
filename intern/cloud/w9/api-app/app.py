# api-app: tiny Flask service with a Prometheus /metrics endpoint.
# ERROR_RATE injects failures (for the bad-canary demo); VERSION tags responses.
import os
import random
from flask import Flask, jsonify
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
PrometheusMetrics(app)  # auto-adds /metrics (flask_http_request_total, etc.)

ERR = float(os.getenv("ERROR_RATE", "0"))   # 0.0 .. 1.0 chance of a 500
VER = os.getenv("VERSION", "v1")


@app.get("/")
def index():
    if random.random() < ERR:
        return jsonify(error="injected", version=VER), 500
    return jsonify(ok=True, version=VER)


@app.get("/healthz")
def healthz():
    return "ok", 200
