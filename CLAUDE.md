<!-- entire-graph:begin -->
This repo has the entire-graph code graph installed. Before exploring code with
grep/find/whole-file reads, read .entire/graph-agent.md — resolution-first guidance
for using graph retrieval, focused source inspection, and verification.
@.entire/graph-agent.md
<!-- entire-graph:end -->

## Session history (Entire checkpoints)

Past agent sessions are recorded as Entire checkpoints. Before re-deciding something
or changing code whose intent is unclear, check history instead of guessing:

    entire checkpoint list                    # recent sessions/commits on this branch
    entire checkpoint explain <id|sha>        # prompt + summary (--full for transcript)
    entire why <file>:<line>                  # commit, checkpoint, prompt behind a line
    entire search --compact "<query>"         # needs `entire login`
    entire experts <path|query> --json        # needs `entire login`, mirrored repo

Team rules (commit every step, contracts first, stay in your paths): @AGENTS.md
