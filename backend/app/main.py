"""HTTP API (contract: docs/API.md)."""

from __future__ import annotations

import asyncio
import json
import logging
import re
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FutureTimeout
from datetime import datetime
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse

from . import __version__, a2ui, fallback
from .agent import run_agent
from .calendar_source import get_calendar, mock_calendar
from .compose import plain_turn
from .config import settings
from .fmt import parse_dt
from .models import A2UIActionMessage, ConfirmRequest, IntentRequest, Profile, ProfileUpdate, VoiceTokenRequest
from .state import store
from .tools import RequestCtx, execute_op

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("micro_intent")

app = FastAPI(title="Micro Intent API", version=__version__)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

_pool = ThreadPoolExecutor(max_workers=8)


def _ctx(req: IntentRequest) -> RequestCtx:
    now = datetime.now(settings.tz)
    if req.now:
        try:
            now = parse_dt(req.now)
        except ValueError:
            pass
    return RequestCtx(profile=store.profile, now=now, locale=req.locale or store.profile.locale, url=req.context.url)


def plan_turn(req: IntentRequest) -> dict[str, Any]:
    """Gemini agent with a hard deadline; the scripted planner takes over on any failure."""
    if settings.gemini_api_key and not settings.force_fallback:
        future = _pool.submit(run_agent, req, _ctx(req))
        try:
            return future.result(timeout=settings.agent_timeout_s)
        except FutureTimeout:
            log.warning("agent timed out after %ss, using fallback", settings.agent_timeout_s)
        except Exception as exc:
            log.warning("agent failed, using fallback: %s: %s", type(exc).__name__, exc)
    try:
        return fallback.plan(req, _ctx(req))
    except Exception as exc:
        log.exception("fallback failed")
        locale = req.locale or store.profile.locale
        say = "Das hat gerade nicht geklappt. Versuch es nochmal." if locale == "de" else "Sorry, that did not work. Please try again."
        return plain_turn(say, "fallback") | {"error": f"{type(exc).__name__}: {exc}"}


@app.post("/intent")
def intent(req: IntentRequest) -> dict[str, Any]:
    return plan_turn(req)


def _filler(req: IntentRequest) -> str:
    de = (req.locale or store.profile.locale) == "de"
    travel = re.search(r"get there|train|travel|from|zug|hinkommen|von", req.intent, re.IGNORECASE)
    cal = re.search(r"free|busy|calendar|frei|zeit|kalender", req.intent, re.IGNORECASE)
    if travel and cal:
        return "Ich prüfe deinen Kalender und die Züge." if de else "Checking your calendar and trains."
    if travel:
        return "Ich schaue nach Verbindungen." if de else "Looking up connections."
    if cal:
        return "Ich schaue in deinen Kalender." if de else "Checking your calendar."
    return "Einen Moment." if de else "One moment."


def _sse(event: str, data: dict[str, Any]) -> str:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


@app.post("/intent/stream")
async def intent_stream(req: IntentRequest) -> StreamingResponse:
    async def events():
        yield _sse("orb", {"state": "thinking"})
        yield _sse("filler", {"say": _filler(req)})
        yield _sse("orb", {"state": "searching"})
        turn = await asyncio.to_thread(plan_turn, req)
        yield _sse("turn", turn)

    return StreamingResponse(events(), media_type="text/event-stream", headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


# ---------- human checkpoint ----------

_REJECT_SAY = {
    "reject": {"en": "Okay, I won't do that.", "de": "Okay, mache ich nicht."},
    "skip": {"en": "Okay, skipping the event.", "de": "Okay, du lässt den Termin aus."},
    "keep": {"en": "Okay, keeping both as they are.", "de": "Okay, beides bleibt wie es ist."},
}


def handle_action(name: str, action_id: str, edits: dict[str, Any], surface_id: str | None) -> JSONResponse:
    locale = store.profile.locale
    if name not in {"confirm", *_REJECT_SAY}:
        raise HTTPException(422, f"unknown action name {name}")
    act = store.get_action(action_id) if action_id else None
    if act is None and not (action_id == "" and name in {"skip", "keep"}):
        return JSONResponse(
            {"action_id": action_id, "status": "not_found", "message": "Unknown or expired action."} | plain_turn("", "agent"),
            status_code=404,
        )
    sid = surface_id or (act.surface_id if act else None)
    cards = [a2ui.delete_surface(sid)] if sid else []
    if act is not None and act.status != "pending":
        return JSONResponse(
            {"action_id": action_id, "status": "already_done", "message": f"Already {act.status}.", "result": act.result} | plain_turn("", "agent")
        )

    if name != "confirm":
        if act is not None:
            act.status = "rejected"
        say = _REJECT_SAY[name].get(locale, _REJECT_SAY[name]["en"])
        return JSONResponse({"action_id": action_id, "status": "rejected", "message": say} | plain_turn(say, "agent", cards))

    with store.lock:
        if act.status != "pending":
            return JSONResponse({"action_id": action_id, "status": "already_done", "message": f"Already {act.status}."} | plain_turn("", "agent"))
        act.status = "running"
    try:
        results = [execute_op(op, edits) for op in act.ops]
    except Exception as exc:
        act.status = "pending"
        log.warning("action %s failed: %s", action_id, exc)
        msg = f"{type(exc).__name__}: {exc}"
        say = "Das hat nicht geklappt." if locale == "de" else "That did not work."
        return JSONResponse({"action_id": action_id, "status": "failed", "message": msg} | plain_turn(say, "agent"))
    act.status = "done"
    act.result = results[0] if len(results) == 1 else {"results": results}
    message = " ".join(r.get("message", "") for r in results).strip()
    say = ("Erledigt. " if locale == "de" else "Done. ") + message
    return JSONResponse({"action_id": action_id, "status": "done", "message": message, "result": act.result} | plain_turn(say, "agent", cards))


@app.post("/action")
def action(msg: A2UIActionMessage) -> JSONResponse:
    ctx = dict(msg.action.context)
    action_id = str(ctx.pop("action_id", "") or "")
    return handle_action(msg.action.name, action_id, ctx, msg.action.surfaceId)


@app.post("/confirm")
def confirm(req: ConfirmRequest) -> JSONResponse:
    return handle_action("confirm" if req.approved else "reject", req.action_id, req.edits or {}, None)


# ---------- profile, voice, ops ----------


@app.get("/profile")
def get_profile() -> Profile:
    return store.profile


@app.put("/profile")
def put_profile(upd: ProfileUpdate) -> Profile:
    return store.update_profile(upd)


@app.post("/voice/token")
def voice_token(_: VoiceTokenRequest | None = None) -> dict[str, Any]:
    if not settings.gemini_api_key:
        raise HTTPException(503, "voice is not configured (no Gemini key on the backend)")
    from .voice import mint_live_token

    try:
        return {"provider": "gemini-live"} | mint_live_token()
    except Exception as exc:
        log.warning("voice token failed: %s", exc)
        raise HTTPException(502, f"could not mint a Gemini Live token: {type(exc).__name__}") from exc


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "version": __version__,
        "model": settings.model,
        "calendar": get_calendar().name,
        "gemini": bool(settings.gemini_api_key),
        "force_fallback": settings.force_fallback,
    }


@app.post("/demo/reset")
def demo_reset() -> dict[str, bool]:
    mock_calendar.reset()
    store.reset()
    return {"ok": True}
