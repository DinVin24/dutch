---
description: Create a git commit using the strict Conventional Commits format
---

All agents must strictly follow the Conventional Commits format when saving code. 

1. Formulate a commit message matching the format: `<type>(<scope>): <description>`.
2. Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
3. Provide a clear, imperative description.
4. Execute the commit command using `git commit -m`.
// turbo
`git commit -m "<your conventional message>"`
