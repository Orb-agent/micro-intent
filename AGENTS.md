<!-- entire-graph:begin -->
This repo has the entire-graph code graph installed. Before exploring code with
grep/find/whole-file reads, read .entire/graph-agent.md — resolution-first guidance
for using graph retrieval, focused source inspection, and verification.
@.entire/graph-agent.md
<!-- entire-graph:end -->

## Team rules for every agent

1. **Commit every step.** As soon as a task's check passes, commit it: a small Conventional Commit (`feat(voice): stream TTS`) on your package branch `feature/wpN-<name>`. Merge into `develop` at the checkpoints. Never end a session with finished work uncommitted.
2. **Contracts first.** `docs/contracts.md` is the API between packages. Change it only by agreement, in the same commit as the code that needs it.
3. **Stay in your paths.** Each package owns the paths listed in `docs/work-packages.md`.
4. **Never commit secrets or generated files:** `.env`, tokens, recorded audio, build output.
5. **Tests use fixtures.** Live Gradium, Gemini, Google and SBB calls only in the checks a plan names.
