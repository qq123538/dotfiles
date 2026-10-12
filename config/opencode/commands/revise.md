---
description: Revise a document with targeted edits — no narration, no meta-commentary in the file
agent: doc-editor
---

Revise a document on disk.

## Target and instructions

$ARGUMENTS

If no target file or no instructions were given, ask for the missing part
and stop.

## Workflow

1. Read the target file first. The file on disk is the only source of truth.
2. Identify every location the instructions apply to.
3. Apply each change with the edit tool — small, targeted edits. Rewrite the
   whole file only if explicitly requested.
4. Stop after the last edit. The document must read as a clean final version.

## Output

One line per change: location + what changed. No document content in the
reply.
