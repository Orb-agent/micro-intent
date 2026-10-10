import json

import httpx
import pytest

import voice

BRIEF = "A calm Swiss German male voice, 40 to 55, warm and steady, for a train conductor."


@pytest.fixture
def gradium(monkeypatch):
    """httpx without network: Gradium's Voice Design endpoints, the candidate ready on the 3rd poll."""
    monkeypatch.setenv("GRADIUM_API_KEY", "test-key")
    monkeypatch.setattr(voice, "DESIGN_POLL_S", 0)
    state = {"requests": [], "ready_after": 3}

    def handler(request):
        state["requests"].append(request)
        assert request.headers["x-api-key"] == "test-key"
        if request.url.path == "/api/voice-generator/generate":
            return httpx.Response(201, json={"embeddings": [{"embedding_id": "vox_emb_abc123", "ready": False}]})
        if request.url.path == "/api/voice-generator/embeddings":
            polls = sum(r.url.path == request.url.path for r in state["requests"])
            return httpx.Response(200, json={"embeddings": [{"embedding_id": "vox_emb_abc123", "ready": polls >= state["ready_after"]}]})
        if request.url.path == "/api/voices/from-embedding":
            return httpx.Response(201, json={"uid": "VoiceUid123"})
        if request.url.path == "/api/voices/":
            return httpx.Response(200, json=state.get("library", []))
        return httpx.Response(404, json={"detail": "Not Found"})

    real = httpx.AsyncClient
    monkeypatch.setattr(httpx, "AsyncClient", lambda **kw: real(transport=httpx.MockTransport(handler), **kw))
    return state


async def test_design_waits_for_the_candidate_then_converts_it(gradium):
    assert await voice.design_voice(BRIEF, "de") == "VoiceUid123"

    generate, *polls, convert = gradium["requests"]
    assert json.loads(generate.content) == {"prompt": BRIEF, "language": "de", "json_config": {"cfg_scale": 10.0}}
    assert len(polls) == 3 and polls[0].url.params["embedding_id"] == "vox_emb_abc123"
    assert json.loads(convert.content) == {
        "voxium_embedding_id": "vox_emb_abc123", "name": "Beaver abc123", "description": BRIEF,
    }  # fmt: skip


async def test_candidate_never_ready_times_out(gradium, monkeypatch):
    gradium["ready_after"] = float("inf")
    monkeypatch.setattr(voice, "DESIGN_TIMEOUT_S", 0)
    with pytest.raises(TimeoutError):
        await voice.design_voice(BRIEF)
    assert not any(r.url.path.endswith("from-embedding") for r in gradium["requests"])


async def test_mood_voice_is_designed_once_then_cached(gradium, monkeypatch):
    monkeypatch.setattr(voice, "_mood_voices", {})
    assert await voice.mood_voice("stressed") == "VoiceUid123"
    assert await voice.mood_voice("stressed") == "VoiceUid123"

    paths = [r.url.path.removeprefix("/api") for r in gradium["requests"]]
    assert paths.count("/voices/") == 1 and paths.count("/voice-generator/generate") == 1  # the 2nd call: cache
    convert = next(r for r in gradium["requests"] if r.url.path.endswith("from-embedding"))
    assert json.loads(convert.content)["name"] == "Beaver mood stressed"
    assert json.loads(gradium["requests"][1].content)["prompt"] == voice.MOOD_BRIEFS["stressed"]


async def test_mood_voice_reuses_the_library_voice_across_restarts(gradium, monkeypatch):
    monkeypatch.setattr(voice, "_mood_voices", {})
    gradium["library"] = [{"uid": "Other", "name": "Beaver"}, {"uid": "HappyUid", "name": "Beaver mood happy"}]
    assert await voice.mood_voice("happy") == "HappyUid"
    assert await voice.mood_voice("neutral") is None
    assert [r.url.path for r in gradium["requests"]] == ["/api/voices/"]  # no design, no slot used
