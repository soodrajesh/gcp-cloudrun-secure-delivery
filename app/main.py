"""quote: a tiny price-quote API used to demonstrate the delivery pipeline.

APP_VERSION is baked in at build time; ERROR_RATE (0-100) is a deliberate fault switch used to
demonstrate that a bad release is caught by the canary and rolled back.
"""

import os
import random

from flask import Flask, jsonify

app = Flask(__name__)
VERSION = os.environ.get("APP_VERSION", "dev")
ERROR_RATE = float(os.environ.get("ERROR_RATE", "0"))
ENVIRONMENT = os.environ.get("ENVIRONMENT", "local")
PRICES = {"EUR": 1.0, "USD": 1.09, "GBP": 0.85}


def should_fail(rate: float = ERROR_RATE, roll: float | None = None) -> bool:
    return (random.random() * 100 if roll is None else roll) < rate


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/")
def quote():
    if should_fail():
        return jsonify(error="injected fault"), 500
    resp = jsonify(
        service="quote", version=VERSION, environment=ENVIRONMENT, revision=os.environ.get("K_REVISION", "local"), prices=PRICES
    )
    resp.headers["X-App-Version"] = VERSION
    return resp
