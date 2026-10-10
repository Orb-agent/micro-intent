import json
from types import SimpleNamespace

import aiohttp

import voice


def step(p2, p_other=0.9):
    """A `step` whose 2.0 s horizon is not at index 2, so picking by index would read p_other."""
    return {"type": "step", "vad": [
        {"horizon_s": 0.5, "inactivity_prob": p_other},
        {"horizon_s": 2.0, "inactivity_prob": p2},
        {"horizon_s": 1.0, "inactivity_prob": p_other},
        {"horizon_s": 3.0, "inactivity_prob": p_other},
    ]}


def text(t):
    return {"type": "text", "text": t, "start_s": 0.0}


def test_end_of_turn_rule():
    turn = voice.TurnDetector()
    assert not any(turn.feed(step(0.99)) for _ in range(5))  # silence before any words: no turn
    assert not turn.feed(text("Can"))
    assert not turn.feed(text(" "))  # blank segments are not words
    assert [turn.feed(step(0.9)) for _ in range(2)] == [False, False]
    assert not turn.feed(step(0.4, p_other=0.99))  # 2.0 s horizon dips: the streak restarts
    assert not turn.feed(text("I"))
    assert [turn.feed(step(0.6, p_other=0.0)) for _ in range(3)] == [False, False, True]
    assert turn.take() == "Can I"
    assert not any(turn.feed(step(0.99)) for _ in range(5))  # next turn starts empty


async def test_flush_then_emit_one_turn():
    msgs = [text("Can"), text("I"), step(0.9), step(0.9), step(0.9), step(0.9),
            text("go"), {"type": "flushed", "flush_id": 0}, text("Next")]
    events, flushes = [], []

    async def frames():
        for m in msgs:
            yield SimpleNamespace(type=aiohttp.WSMsgType.TEXT, data=json.dumps(m))

    async def send_flush():
        flushes.append(len(events))

    async def on_speech():
        events.append("speech")

    async def on_turn(t):
        events.append(t)

    stt = SimpleNamespace(_ws=frames(), send_flush=send_flush)
    await voice.ContinuousTranscriber(on_speech, on_turn)._listen(stt)
    assert events == ["speech", "Can I go", "speech"]  # the word after `flush` joins the turn
    assert flushes == [1]  # one flush, after the first words
