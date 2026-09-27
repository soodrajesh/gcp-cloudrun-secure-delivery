from app.main import app, should_fail


def test_health():
    assert app.test_client().get("/health").get_json() == {"status": "ok"}


def test_quote_shape_and_version_header():
    r = app.test_client().get("/")
    assert r.status_code == 200
    body = r.get_json()
    assert body["service"] == "quote" and body["prices"]["EUR"] == 1.0
    assert r.headers["X-App-Version"] == body["version"]


def test_fault_switch_is_deterministic():
    assert should_fail(rate=50, roll=10) is True
    assert should_fail(rate=50, roll=60) is False
    assert should_fail(rate=0, roll=0) is False
