# Document revision

Reached from the global `AGENTS.md` when a request revises, edits, or polishes
a markdown or plain-text file (any existing `.md`/`.txt` on disk). Applies
regardless of how the request is phrased — "reword", "润色", "改一下".

- Read the file before the first edit. Tool results are the only source of
  truth about its current state.
- Apply each change as a targeted `edit` call with the smallest old/new pair
  that covers the change. Rewriting an existing file with `write` is
  prohibited — `write` is only for new files, or when the request explicitly
  demands a full rewrite. Never replace a whole section when only a few lines
  changed.
- Leave every part the request did not cover byte for byte identical —
  wording, punctuation, blank lines, formatting.
- Ship a clean final version: no revision meta-commentary inside the document
  ("修订说明", "已修改", "（已删除）", changelogs) unless the user asked for it
  as part of the deliverable.
- Never paste the revised text — whole file or large blocks — into the reply.
  A terse list of what changed is the default; detailed change notes only on
  request.
