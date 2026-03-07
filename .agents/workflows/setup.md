---
description: Ensure the repository is configured for Antigravity (Run Once)
---

This workflow applies required global settings to the repository so Antigravity and the humans share the same rules, specifically enforcing Conventional Commits.

1. Configure the `core.hooksPath` to enforce git hooks globally.
// turbo
`git config core.hooksPath .githooks`
