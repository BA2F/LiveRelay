#!/usr/bin/env python3
"""LiveRelay cradle service.

Reads each customer volume under the data directory for
`liverelay-cradle-plan.json`, `liverelay-checkin.json` and
`liverelay-cradle-test.json` (written by the LiveRelay app) and:

* reminds the owner by email once per day after
  `periodDays - remindBeforeDays` without a check-in;
* notifies every recipient once after `periodDays + graceDays` without a
  check-in, using the subject and body the owner wrote in the app (version 1
  plans fall back to the built-in template);
* sends a test mail requested by the app and leaves a result file.

Timing follows trust-boundary decision A in
tasks/specs/2026-10-15_报平安与自动交接.md: the service controls when to
notify and could in principle notify early, while package contents stay
encrypted and are never readable here. Version 2 plans carry the owner's
final email text, including the pickup code when the owner kept it there.

The baseline clock is the check-in file's mtime (server clock), falling
back to the plan file's mtime while no check-in exists. State is one JSON
file per customer under the state directory. CRADLE_DRY_RUN=1 logs mail
instead of sending it.
"""

from __future__ import annotations

import json
import os
import smtplib
import ssl
import time
from datetime import datetime, timezone
from email.message import EmailMessage
from pathlib import Path

DATA_DIR = Path(os.environ.get("CRADLE_DATA_DIR", "/data"))
STATE_DIR = Path(os.environ.get("CRADLE_STATE_DIR", "/state"))
INTERVAL_SECONDS = int(os.environ.get("CRADLE_INTERVAL_SECONDS", "600"))
DRY_RUN = os.environ.get("CRADLE_DRY_RUN", "") == "1"
ONCE = os.environ.get("CRADLE_ONCE", "") == "1"

CHECKIN_NAME = "liverelay-checkin.json"
PLAN_NAME = "liverelay-cradle-plan.json"
TEST_NAME = "liverelay-cradle-test.json"
TEST_RESULT_NAME = "liverelay-cradle-test-result.json"
PLAN_KIND = "liverelay-cradle-plan"
PLAN_VERSIONS = (1, 2)
RECIPIENT_FIELDS = ("label", "email", "package", "cloudUrl", "cloudUser", "cloudPassword")


def log(message: str) -> None:
    stamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[cradle {stamp}] {message}", flush=True)


def read_json(path: Path):
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def write_state(path: Path, state: dict) -> None:
    tmp = path.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False, indent=2)
    tmp.replace(path)


def send_mail(to: str, subject: str, body: str) -> None:
    if DRY_RUN:
        log(f"DRY-RUN mail to {to}: {subject}")
        return
    host = os.environ["CRADLE_SMTP_HOST"]
    port = int(os.environ.get("CRADLE_SMTP_PORT", "465"))
    user = os.environ["CRADLE_SMTP_USER"]
    password = os.environ["CRADLE_SMTP_PASS"]
    sender = os.environ["CRADLE_SMTP_FROM"]
    mode = os.environ.get("CRADLE_SMTP_MODE", "ssl")
    message = EmailMessage()
    message["From"] = sender
    message["To"] = to
    message["Subject"] = subject
    message.set_content(body, charset="utf-8")
    if mode == "starttls":
        with smtplib.SMTP(host, port, timeout=30) as smtp:
            smtp.starttls(context=ssl.create_default_context())
            smtp.login(user, password)
            smtp.send_message(message)
    else:
        with smtplib.SMTP_SSL(
            host, port, timeout=30, context=ssl.create_default_context()
        ) as smtp:
            smtp.login(user, password)
            smtp.send_message(message)


def plan_problem(plan) -> str | None:
    """Mirror of the app-side CradlePlan.validationError; returns the first
    problem found, or None when the plan is usable."""
    if not isinstance(plan, dict):
        return "not an object"
    if plan.get("kind") != PLAN_KIND or plan.get("version") not in PLAN_VERSIONS:
        return "kind/version"
    owner_email = plan.get("ownerEmail")
    period = plan.get("periodDays")
    remind = plan.get("remindBeforeDays")
    grace = plan.get("graceDays")
    if not isinstance(owner_email, str) or "@" not in owner_email:
        return "ownerEmail"
    if not isinstance(period, int) or isinstance(period, bool) or not 1 <= period <= 365:
        return "periodDays"
    if not isinstance(remind, int) or isinstance(remind, bool) or not 0 <= remind < period:
        return "remindBeforeDays"
    if not isinstance(grace, int) or isinstance(grace, bool) or not 0 <= grace <= 90:
        return "graceDays"
    recipients = plan.get("recipients")
    if not isinstance(recipients, list):
        return "recipients"
    version = plan.get("version")
    for recipient in recipients:
        if not isinstance(recipient, dict):
            return "recipient"
        for key in RECIPIENT_FIELDS:
            value = recipient.get(key)
            if not isinstance(value, str) or not value:
                return f"recipient.{key}"
        if version == 2:
            subject = recipient.get("subject")
            body = recipient.get("body")
            if not isinstance(subject, str) or not subject.strip() or len(subject) > 500:
                return "recipient.subject"
            if not isinstance(body, str) or not body.strip() or len(body) > 20000:
                return "recipient.body"
    return None


def test_problem(request) -> str | None:
    if not isinstance(request, dict):
        return "not an object"
    if request.get("kind") != "liverelay-cradle-test" or request.get("version") != 1:
        return "kind/version"
    to = request.get("to")
    subject = request.get("subject")
    body = request.get("body")
    if not isinstance(to, str) or "@" not in to or len(to) > 300:
        return "to"
    if not isinstance(subject, str) or not subject.strip() or len(subject) > 500:
        return "subject"
    if not isinstance(body, str) or not body.strip() or len(body) > 20000:
        return "body"
    return None


def process_test(customer: Path, now: datetime) -> None:
    """Sends a test mail requested by the app and leaves a result file.

    The request is removed even when invalid, so the app's next check of the
    result can report the failure instead of retrying forever.
    """
    path = customer / TEST_NAME
    if not path.is_file():
        return
    request = read_json(path)
    result = {
        "kind": "liverelay-cradle-test-result",
        "version": 1,
        "requestedAt": request.get("requestedAt") if isinstance(request, dict) else None,
        "sentAt": None,
        "error": None,
    }
    problem = test_problem(request)
    if problem:
        result["error"] = f"invalid test request ({problem})"
    else:
        try:
            send_mail(request["to"], request["subject"], request["body"])
        except Exception as error:  # noqa: BLE001 - reported to the app
            result["error"] = str(error)
        else:
            result["sentAt"] = now.isoformat()
    try:
        write_state(customer / TEST_RESULT_NAME, result)
        path.unlink(missing_ok=True)
    except OSError as error:
        log(f"{customer}: test result write/remove failed: {error}")


def remind_subject(plan: dict, days: float) -> str:
    return f"【留灯】你已经 {days:.0f} 天没有报平安"


def remind_body(plan: dict, days: float) -> str:
    trigger_at = plan["periodDays"] + plan["graceDays"]
    return (
        "这是留灯（LiveRelay）的报平安提醒。\n\n"
        f"距离你上一次报平安已经 {days:.0f} 天（你设定的周期是 {plan['periodDays']} 天）。\n"
        "如果一切正常，打开 App 点一下「报平安」即可。\n\n"
        f"如果再过约 {max(trigger_at - days, 0):.0f} 天仍没有你的报平安，"
        "系统会按你的预先授权，把取件信息发送给你指定的接收者。\n"
    )


def notify_subject(recipient: dict) -> str:
    return f"【留灯】{recipient['label']} 给你留了内容"


def notify_body(recipient: dict, plan: dict) -> str:
    return (
        f"{recipient['label']} 在留灯（LiveRelay）里预先授权：如果他长期没有再报平安，"
        "就把下面的取件信息交给你。\n\n"
        f"云端网址：{recipient['cloudUrl']}\n"
        f"账号：{recipient['cloudUser']}\n"
        f"密码：{recipient['cloudPassword']}\n"
        f"要下载的文件：{recipient['package']}\n\n"
        "步骤：\n"
        f"1. 用浏览器打开网址，登录下载 {recipient['package']} 文件。\n"
        "2. 用 LiveRelay App 打开这个文件（需要你手上的身份文件，如已布置）。\n\n"
        "如果可能，请先试着联系他本人确认情况。\n"
    )


def find_customers() -> list[tuple[str, Path]]:
    """Directories holding cradle files, keyed by path relative to the data
    root. The deployed copyparty layout puts customer volumes one level
    deeper (users/<customer>/), so a fixed one-level scan is not enough:
    walk up to three levels and treat any directory containing one of the
    cradle files as a customer."""
    root_parts = len(DATA_DIR.parts)
    customers: list[tuple[str, Path]] = []
    for dirpath, dirnames, filenames in os.walk(DATA_DIR):
        if len(Path(dirpath).parts) - root_parts >= 3:
            dirnames[:] = []
            continue
        if CHECKIN_NAME in filenames or PLAN_NAME in filenames or TEST_NAME in filenames:
            relative = Path(dirpath).relative_to(DATA_DIR)
            customers.append(("__".join(relative.parts), Path(dirpath)))
    return sorted(customers)


def process_customer(key: str, customer: Path, now: datetime) -> None:
    process_test(customer, now)
    plan_path = customer / PLAN_NAME
    if not plan_path.is_file():
        return
    plan = read_json(plan_path)
    problem = plan_problem(plan)
    if problem:
        log(f"{key}: invalid plan ({problem}); skipped")
        return

    checkin_path = customer / CHECKIN_NAME
    baseline_path = checkin_path if checkin_path.is_file() else plan_path
    baseline_ns = baseline_path.stat().st_mtime_ns

    state_path = STATE_DIR / f"{key}.json"
    state = read_json(state_path)
    if not isinstance(state, dict) or state.get("baselineNs") != baseline_ns:
        log(f"{key}: baseline is {baseline_path.name} ({baseline_ns})")
        state = {"baselineNs": baseline_ns, "lastRemindDate": None, "notified": {}}
    notified = state.get("notified")
    if not isinstance(notified, dict):
        notified = {}
    state["notified"] = notified

    days = (now.timestamp() - baseline_ns / 1_000_000_000) / 86400.0
    remind_at = plan["periodDays"] - plan["remindBeforeDays"]
    trigger_at = plan["periodDays"] + plan["graceDays"]
    today = now.astimezone().date().isoformat()

    if days >= trigger_at:
        for recipient in plan["recipients"]:
            email = recipient["email"]
            if email in notified:
                continue
            subject = recipient.get("subject") or notify_subject(recipient)
            body = recipient.get("body") or notify_body(recipient, plan)
            try:
                send_mail(email, subject, body)
            except Exception as error:  # noqa: BLE001 - logged, retried next round
                log(f"{key}: notify {email} failed: {error}")
                continue
            notified[email] = now.isoformat()
            log(f"{key}: notified {email} after {days:.1f} days")
    elif days >= remind_at and state.get("lastRemindDate") != today:
        try:
            send_mail(plan["ownerEmail"], remind_subject(plan, days), remind_body(plan, days))
        except Exception as error:  # noqa: BLE001 - logged, retried next round
            log(f"{key}: reminder failed: {error}")
        else:
            state["lastRemindDate"] = today
            log(f"{key}: reminded {plan['ownerEmail']} after {days:.1f} days")

    write_state(state_path, state)


def main() -> None:
    log(
        f"starting: data={DATA_DIR} state={STATE_DIR} "
        f"interval={INTERVAL_SECONDS}s dry_run={DRY_RUN}"
    )
    if not DRY_RUN:
        missing = [
            key
            for key in (
                "CRADLE_SMTP_HOST",
                "CRADLE_SMTP_USER",
                "CRADLE_SMTP_PASS",
                "CRADLE_SMTP_FROM",
            )
            if not os.environ.get(key) or os.environ.get(key) == "CHANGE-ME"
        ]
        if missing:
            log(f"missing SMTP settings: {', '.join(missing)}; refusing to start")
            raise SystemExit(2)
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    while True:
        now = datetime.now(timezone.utc)
        try:
            customers = find_customers()
        except OSError as error:
            log(f"data directory unreadable: {error}")
            customers = []
        for key, customer in customers:
            try:
                process_customer(key, customer, now)
            except Exception as error:  # noqa: BLE001 - one bad customer never stops the loop
                log(f"{key}: unexpected error: {error}")
        if ONCE:
            return
        time.sleep(INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
