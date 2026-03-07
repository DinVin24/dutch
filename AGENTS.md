# AGENTS

## Mission
Ship the rules-heavy Dutch card game in Godot with a four-person crew that treats every instruction as an opportunity to leverage agentic AI (yourself included). Always keep the README.md rule set front and center: cards stay face down except on draws/swaps/jumps, point values are Ace=1 through King=13 (King of Diamonds = 0), and special moves like Jump-In, Queen, Jack, and the Dutch call govern turn flow and scoring.

## Roles & Responsibilities
Here, agents act as Full-Stack Developers working on vertical slices (Epics) rather than horizontally across domains. Roles are divided by **Development Phase**:

1. **The Planner (Agent 1 / Architecture & Planning)**
   - Focuses solely on reading game rules, generating User Stories (Epics), and writing an `implementation_plan.md` for the next vertical slice.
   - Does not write directly to project code files.
2. **The Executor (Agent 2 / Coding & Implementation)**
   - Takes the `implementation_plan.md` from The Planner and writes/modifies all necessary UI, Scripts, and Scenes to make that vertical slice function perfectly.
   - Owns the `task.md` execution flow. 
3. **The Validator (Agent 3 / QA & Validation)**
   - Reviews The Executor's commit, plays the game, tests the edge cases in the user stories, and writes the `walkthrough.md`.
   - **PR Verification:** Explicitly verifies Pull Requests against the `implementation_plan.md` and README rules before handoff.
   - If bugs exist, it shifts the pipeline back to The Executor.
4. **The Reviewer (Agent 4 / Integration & Handoff)**
   - Ensures Conventional Commits were used and successfully Squash-Merges the Pull Request into a `develop` or `epic/*` branch (avoid merging directly to `main`).
   - **Jira Sync:** Periodically runs `gh pr list --state all` and `git log` to identify teammate/agent progress.
   - **Mapping & Transitions:** Maps features to Jira tickets and transitions them through all categories (**Backlog**, **Planning**, **Execution**, **Validation**, **Done**) based on Git/PR state.
   - Prompts The Planner to begin the next Epic.

## Agentic Guidelines
- Treat yourself as an agent with foresight: proactively suggest follow-up tests, request missing assets, and double-check README rules before changing gameplay code.
- Use specialized AI tools (e.g. Gemini for layout tasks, ChatGPT Codex for generic scripts) as appropriate, but always keep descriptions and commits human-readable.
- Each commit/message should follow **Conventional Commits** format (e.g. `feat(ui): implement pause menu`, `fix(logic): correct scoring rule`). Include the Agent role and a descriptive summary in the body.
- When merging Pull Requests, always use **Squash and Merge** into `develop` or `epic/*` branches to keep the history linear. Direct merges to `main` should only occur for stable releases.
- **Human + AI Pairing:** Each Human+AI pair owns an entire Epic (vertical slice) from start to finish. This eliminates synchronous dependencies (e.g., waiting on someone else to build the UI) and prevents merge conflicts.
- **Never Work on Completed Stories:** Agents must never work on a story marked as completed (`[x]`) in `user_stories.md`. Once a story is checked, it is considered finalized and locked. Any changes to completed features require an explicit user request or a documented bug fix (mapped to a new task).
- Never change the git email and user name.

## Coordination
- Before editing a file owned by another role, confirm whether a dependency or signal hookup is required and note it in your update.
- Send status updates like “Card Engine: data resource now exposes suit/rank/points; awaiting Game Flow review” so the crew knows why the branch moved.
- Always run `git status` before and after major changes to avoid conflicts with the other agents.

## Verification & Handoff
- When a feature touches gameplay (Jump-In rules, scoring, ending the game), pair it with a short manual test plan or automated script that validates the README scenarios.
- Document any assumptions (e.g., “Jump-In triggered when discarded card matches without turn change”) so later agents can re-evaluate them.

## Safety Notes
- The “Google Antigravity” work you inherited is part of this repo’s narrative; treat it as a reference but not a requirement. When in doubt, follow the authoritative README.
- If a new team member or agent requests clarification, prefer a short question to avoid delivering the wrong implementation.
