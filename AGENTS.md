# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- `docs/API.md` is the contract every part builds against in parallel; any change goes into its Changelog and the PR description.
- Generative UI is A2UI v0.9.1 with the custom catalog in `docs/API.md`; the agent only picks components, the backend (`backend/app/compose.py`) fills them with tool data.
- Human checkpoint: write tools only create pending actions; execution happens solely in `/action` / `/confirm` (`backend/app/main.py`).
- Backend setup, demo path, smoke test and deploy: `backend/README.md`. Secrets never go into the repo; the Gemini key is loaded from `~/.config/micro-intent/gemini.env`.
- `gemini-3.8-live` rejects TEXT-only responses; use AUDIO with `inputAudioTranscription` for speech-to-text.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
