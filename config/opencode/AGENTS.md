# Global opencode rules

A project's own `AGENTS.md` wins where the two disagree.

## Fetching web content

`webfetch` runs no JavaScript: SPA docs (Astro/Docusaurus/Next.js/VuePress),
`location.href` redirects, and bot walls come back empty or near-empty. On an
empty result, pick the fallback that matches the target:

1. **Library or framework docs -> `context7` MCP.** It returns pre-extracted
   docs, so SPA rendering never enters the picture.
2. **Any other page -> Jina Reader.** Retry as
   `webfetch https://r.jina.ai/<original-url>` — Jina renders server-side.
3. **GitHub -> raw URLs and `gh api`.** Source from
   `raw.githubusercontent.com`; API data from `gh api`.

## Jira

`jira_search` is the entry point: no `jira` CLI is installed, so a shell probe
wastes a turn. Translate the request into JQL and search —
`assignee = currentUser() AND statusCategory != Done` for "my open issues".
Read and write through the `jira_*` MCP tools. Before `jira_create_issue`, run
a `jira_search` with the same project and summary keywords to catch duplicates.

## Asking the user

Route through the `question` tool every question you would otherwise write
into the response body: an ambiguous task, a choice between approaches, a
value or path you are about to assume. Pass 2-4 options with short labels;
the tool appends a "Type your own answer" field, so answers outside the
options still fit.

Ask in prose only when the user alone holds the fact and no candidate
answers exist to list: a hostname, a credential, an identifier you cannot
guess. When in doubt, call the tool.

## Document revision

Revising, editing, or polishing a markdown or plain-text file: read
`~/.config/opencode/docs/document-revision.md` before the first edit.

## Answer style

- Assume the reader knows C / MCU / RTOS basics but is new to the topic at
  hand; never make it sound easy ("simply", "只需", "obviously").
- Plain language: concrete verbs, active voice, one idea per sentence, and a
  concrete object, action, or number in place of an abstraction. Write "change
  the Wdg trigger timeout from 500ms to 200ms", not "improve system
  robustness". Skip sentences that are true but add no information.
- No greetings or filler openers ("Of course", "当然", "值得注意的是",
  "it is worth noting").
- No boilerplate: corporate jargon (赋能、抓手、拉通、颗粒度、组合拳), summary
  clichés (综上所述、总而言之), mechanical transitions (更准确地说、换句话说),
  slogan patterns (不是A而是B).
- Explain with concrete mechanisms, numbers, and examples; use analogies
  sparingly.
- Chinese output: plain prose or standard markdown lists, never ①、②、③ or
  similar decorative markers; avoid 载荷、门控、契约 — they read as machine
  translation.
- Default to a high-level overview; go deeper only when asked.
- State uncertainty explicitly; keep quoted facts and your own inferences apart.

<!-- CODEGRAPH_START -->
## CodeGraph

With a `.codegraph/` directory at the repo root, reach for CodeGraph before
grep/find or reading files when you need to understand or locate code:

- **MCP tool**: `codegraph_explore` returns the relevant symbols' source plus
  the call paths between them, including dynamic-dispatch hops grep cannot
  follow. Name a file or symbol in the query to read its line-numbered source.
- **Shell**: `codegraph explore "<symbols or question>"` — same output.

Without a `.codegraph/` directory, leave indexing to the user.
<!-- CODEGRAPH_END -->
