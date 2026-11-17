#!/usr/bin/env python3
"""Uptime Kuma webhook → wa_hack_cli.simple_send bridge."""
from __future__ import annotations

import logging
import os
import sys
from functools import wraps
from typing import Any, Callable

from flask import Flask, jsonify, request

from wa_hack_cli import simple_send

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("kuma-wa-bridge")

app = Flask(__name__)


def env(name: str, default: str | None = None) -> str | None:
    value = os.environ.get(name, default)
    if value is None or value == "":
        return default
    return value


def require_config() -> tuple[str, int, str, str]:
    srv = env("WA_SRV")
    port_raw = env("WA_PORT")
    recipient = env("WA_RECIPIENT") or env("WA_ADMIN_NUMBER")
    token = env("WEBHOOK_TOKEN")
    missing = [
        key
        for key, val in (
            ("WA_SRV", srv),
            ("WA_PORT", port_raw),
            ("WA_RECIPIENT or WA_ADMIN_NUMBER", recipient),
            ("WEBHOOK_TOKEN", token),
        )
        if not val
    ]
    if missing:
        raise RuntimeError("Missing required env: " + ", ".join(missing))
    return srv, int(port_raw), recipient, token


def check_token(view: Callable[..., Any]) -> Callable[..., Any]:
    @wraps(view)
    def wrapped(*args: Any, **kwargs: Any):
        try:
            _srv, _port, _recipient, token = require_config()
        except RuntimeError as exc:
            log.error("%s", exc)
            return jsonify({"ok": False, "error": str(exc)}), 500

        auth = request.headers.get("Authorization", "")
        provided = request.headers.get("X-Webhook-Token", "")
        if auth.startswith("Bearer "):
            provided = auth[7:].strip()
        if provided != token:
            return jsonify({"ok": False, "error": "unauthorized"}), 401
        return view(*args, **kwargs)

    return wrapped


def format_message(payload: dict[str, Any]) -> str:
    """Build a short WhatsApp text from a Kuma webhook body."""
    msg = payload.get("msg")
    if isinstance(msg, str) and msg.strip():
        return msg.strip()

    monitor = payload.get("monitor") or {}
    heartbeat = payload.get("heartbeat") or {}
    name = monitor.get("name") or "Uptime Kuma"
    status = heartbeat.get("status")
    status_map = {0: "DOWN", 1: "UP", 2: "PENDING", 3: "MAINTENANCE"}
    status_label = status_map.get(status, "ALERT")
    detail = heartbeat.get("msg") or payload.get("message") or ""
    line = f"[{name}] [{status_label}]"
    if detail:
        line = f"{line} {detail}"
    return line.strip() or "Uptime Kuma notification"


def send_via_wa_hack(srv: str, port: int, recipient: str, text: str) -> None:
    """Send via wa_hack; trap simple_send's sys.exit on connection errors."""

    def _guarded_exit(code: int = 0) -> None:
        raise RuntimeError(f"wa_hack simple_send aborted (exit={code})")

    original_exit = sys.exit
    sys.exit = _guarded_exit  # type: ignore[assignment]
    try:
        simple_send(srv, port, recipient, text)
    finally:
        sys.exit = original_exit  # type: ignore[assignment]


@app.get("/health")
def health():
    try:
        require_config()
        return jsonify({"ok": True}), 200
    except RuntimeError as exc:
        return jsonify({"ok": False, "error": str(exc)}), 500


@app.post("/webhook")
@check_token
def webhook():
    srv, port, recipient, _token = require_config()
    payload = request.get_json(silent=True)
    if payload is None:
        # Kuma custom body may be form-encoded; fall back to raw text.
        raw = request.get_data(as_text=True) or ""
        payload = {"msg": raw.strip()} if raw.strip() else {}

    if not isinstance(payload, dict):
        return jsonify({"ok": False, "error": "JSON object expected"}), 400

    text = format_message(payload)
    log.info("Sending to %s via %s:%s (%d chars)", recipient, srv, port, len(text))
    try:
        send_via_wa_hack(srv, port, recipient, text)
    except Exception as exc:  # noqa: BLE001 - surface to Kuma as HTTP error
        log.exception("Send failed")
        return jsonify({"ok": False, "error": str(exc)}), 502

    return jsonify({"ok": True, "recipient": recipient, "chars": len(text)}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(env("PORT", "8080") or "8080"))
