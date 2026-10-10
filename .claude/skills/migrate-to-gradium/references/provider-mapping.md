# Provider Mapping

Use this reference when migrating code from ElevenLabs, Cartesia, or
Deepgram to Gradium.

## Cartesia to Gradium

Endpoint mapping:

| Flow | Cartesia | Gradium |
| --- | --- | --- |
| One-shot TTS | `POST https://api.cartesia.ai/tts/bytes` | `POST https://api.gradium.ai/api/post/speech/tts` |
| Streaming TTS | `wss://api.cartesia.ai/tts/websocket` | `wss://api.gradium.ai/api/speech/tts` |

Field mapping:

| Cartesia | Gradium |
| --- | --- |
| `transcript` | `text` |
| `voice.id` | `voice_id` |
| `model_id` | `model_name` |
| `output_format.container` | `output_format` |
| `Authorization: Bearer ...` or `X-API-Key` | `x-api-key` |
| `Cartesia-Version` | Remove; not required by Gradium |

Gradium replacement POST:

```json
{
  "text": "Hello from Gradium.",
  "voice_id": "YTpq7expH9539ERJ",
  "output_format": "wav",
  "only_audio": true
}
```

Gradium replacement WebSocket:

```json
{"type":"setup","voice_id":"YTpq7expH9539ERJ","model_name":"default","output_format":"wav"}
{"type":"text","text":"Hello from Gradium."}
{"type":"end_of_stream"}
```

## Deepgram to Gradium

Endpoint mapping:

| Flow | Deepgram | Gradium |
| --- | --- | --- |
| Pre-recorded STT | `POST https://api.deepgram.com/v1/listen` | `POST https://api.gradium.ai/api/post/speech/asr` |
| Streaming STT | `wss://api.deepgram.com/v1/listen` | `wss://api.gradium.ai/api/speech/asr` |
| One-shot TTS | `POST https://api.deepgram.com/v1/speak` | `POST https://api.gradium.ai/api/post/speech/tts` |
| Streaming TTS | `wss://api.deepgram.com/v1/speak` | `wss://api.gradium.ai/api/speech/tts` |

STT mapping:

| Deepgram Listen | Gradium STT |
| --- | --- |
| Audio request body | Same audio request body for POST |
| `Authorization: Token ...` | `x-api-key` |
| Query options such as `model` | Use Gradium `model_name` only if needed |
| Transcript alternatives | Gradium NDJSON/WebSocket `text` messages |
| WebSocket binary audio | JSON `audio` messages with base64 audio |

TTS mapping:

| Deepgram Speak | Gradium TTS |
| --- | --- |
| `model` query parameter | `voice_id` plus optional `model_name` |
| `text` | `text` |
| Output encoding/container options | `output_format` |
| `Authorization: Token ...` | `x-api-key` |

Gradium STT WebSocket:

```json
{"type":"setup","model_name":"default","input_format":"pcm"}
{"type":"audio","audio":"base64_encoded_audio"}
{"type":"end_of_stream"}
```

Gradium TTS WebSocket:

```json
{"type":"setup","voice_id":"YTpq7expH9539ERJ","model_name":"default","output_format":"wav"}
{"type":"text","text":"Hello from Gradium."}
{"type":"end_of_stream"}
```

## ElevenLabs to Gradium

Endpoint mapping:

| Flow | ElevenLabs | Gradium |
| --- | --- | --- |
| One-shot TTS | `POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}` | `POST https://api.gradium.ai/api/post/speech/tts` |
| Streaming TTS | `wss://api.elevenlabs.io/v1/text-to-speech/{voice_id}/stream-input` | `wss://api.gradium.ai/api/speech/tts` |

Field mapping:

| ElevenLabs | Gradium |
| --- | --- |
| `{voice_id}` URL path parameter | `voice_id` body/setup field |
| `text` | `text` |
| `model_id` | `model_name` |
| Output format query/body settings | `output_format` |
| `xi-api-key` | `x-api-key` |

Gradium replacement POST:

```json
{
  "text": "Hello from Gradium.",
  "voice_id": "YTpq7expH9539ERJ",
  "output_format": "wav",
  "only_audio": true
}
```

Gradium replacement WebSocket:

```json
{"type":"setup","voice_id":"YTpq7expH9539ERJ","model_name":"default","output_format":"wav"}
{"type":"text","text":"Hello from Gradium."}
{"type":"end_of_stream"}
```
