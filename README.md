# Micro Intent

Look and say: look at something on a web page, say what you want, and an AI agent gets it done - with a generated UI card instead of a chat window, and a human checkpoint before every action.

Built at the {Tech: Europe} Agentic AI Hack Zurich (2026-10-10).

## Layout

| Path | What |
| --- | --- |
| `backend/` | Python FastAPI service: Gemini agent with tools (SBB, calendar, reminders, message drafts), human checkpoint for every write action. |
| `extension/` | Chrome extension: page context capture, voice intent, card rendering. |
| `webapp/` | Companion web app (profile, demo surface). |
| `docs/API.md` | The HTTP contract between all parts. Change it only together with a note in the PR. |

## Configuration

Copy `.env.example` to `backend/.env` and fill in the values.
`.env` files are gitignored; never commit keys.

## Agent session checkpoints

The repo is set up with [Entire](https://entire.io) (`entire enable --agent claude-code`), so agent sessions are attached to the commits they produced.
Install with `brew install --cask entireio/tap/entire` to get the hooks working locally.
