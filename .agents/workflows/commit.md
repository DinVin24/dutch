---
description: Create a git commit using the strict Conventional Commits format
---

All agents must strictly follow the Conventional Commits format when saving code. 

1. Formulate a commit message matching the format: `<type>(<scope>): <description>`.
2. Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
3. Provide a clear, imperative description.
4. Execute the commit command using `git commit -m`.
5. Use a multi-line format for better GitHub visibility:
   ```bash
   git commit -m "type(scope): short description" -m "" -m "Longer explanation of what was changed and why."
   ```
// turbo
`git commit -m "<title>" -m "" -m "<body>"`
