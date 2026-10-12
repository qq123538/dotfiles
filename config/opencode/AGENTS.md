# Global opencode rules

Applies to every opencode session across all projects. A project's own
`AGENTS.md` layers on top of these and takes precedence. This file lives at
`config/opencode/AGENTS.md` and is symlinked to `~/.config/opencode/AGENTS.md`
by `install.sh link`, so opencode auto-loads it as global rules.

## Web content fetching strategy

`webfetch` does a plain HTTP GET + HTML-to-markdown conversion — it does NOT
execute JavaScript. It returns empty or near-empty content for:
- SPA docs sites (Astro/Docusaurus/Next.js/VuePress) whose first paint is a
  bare `<div id="root">` + JS bundle
- JS-based redirects (`location.href`)
- bot-detection / auth-walled / paywalled pages

Use these fallbacks before giving up on a URL:

1. **Library/framework docs -> use the `context7` MCP** (not `webfetch`). It
   returns pre-extracted docs and bypasses SPA rendering entirely. Prefer it
   for any named library or framework.
2. **Generic pages -> Jina Reader proxy.** Retry as
   `webfetch https://r.jina.ai/<original-url>`. Jina renders server-side and
   returns clean markdown. Free, no API key.
3. **GitHub content -> use `gh` CLI or raw URLs.** Fetch
   `raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>` for source, or
   run `gh api ...` for API data. Do not `webfetch` github.com pages (heavy
   SPA).
4. **Discovery vs retrieval.** Use `websearch` (Exa) to find relevant URLs,
   then `webfetch` to read a specific one. `websearch` is enabled globally via
   `OPENCODE_ENABLE_EXA=1` in `zsh/zshenv.symlink`.

## MCP usage rules

MCP tools are available automatically; these rules set priority so the agent
reaches for the right tool instead of defaulting to a grep/Read crawl.

- **context7**: when the question involves a named library or framework's
  docs/API, use `context7` first rather than `webfetch`-ing the official site.
- **codegraph**: in a project that has a `.codegraph/` index, answer code
  structure / call-path / impact-radius questions with `codegraph_explore`
  instead of grepping file-by-file. If no `.codegraph/` index exists,
  CodeGraph will say so — fall back to built-in `grep`/`read`/`glob`.
- **jira**: for anything Jira-related (search / read / create / update /
  transition / comment on issues), call the `mcp:jira` tools directly —
  `jira_search` (JQL), `jira_get_issue`, `jira_create_issue`,
  `jira_update_issue`, `jira_transition_issue`, `jira_add_comment`. There is
  no `jira` CLI installed, so do NOT run `which jira` / probe `~/.jira*` /
  `~/.config/jira*` — that only wastes a turn. When the request is
  natural-language ("show my open issues"), translate it to a JQL and call
  `jira_search` (e.g. `assignee = currentUser() AND statusCategory != Done`)
  rather than shell-probing. Before `jira_create_issue`, run a `jira_search`
  first (same project + summary keywords) to avoid creating a duplicate.

## Document revision

When revising, editing, or polishing a document (markdown or plain text),
regardless of how the request is phrased:

- Apply changes with the edit/write tools directly. Never paste the revised
  text — whole file or large blocks — into the reply.
- The document stays a clean final version: no revision meta-commentary
  inside it ("修订说明", "已修改", "本节已调整", changelogs, "（已删除）"),
  unless the user explicitly asked for that as part of the deliverable.
- Change notes only when explicitly requested — as a separate chat message,
  never inside the file.
- Each revision round starts by re-reading the file. Tool results are the
  only source of truth about document state; earlier assistant narrations
  about the document are not.
- Change only what the request covers; leave surrounding content untouched.
- For a stricter, permission-enforced protocol use the `doc-editor` agent
  or the `/revise` command.
