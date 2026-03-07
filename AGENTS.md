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
   - If bugs exist, it shifts the pipeline back to The Executor. The Validator **MUST** provide exact reproduction steps (initial state, actions taken, expected result, actual result) so The Executor can fix issues surgically without guessing.
4. **The Reviewer (Agent 4 / Integration & Handoff)**
   - Ensures Conventional Commits were used and successfully Squash-Merges the Pull Request into a `develop` or `epic/*` branch (avoid merging directly to `main`).
   - **Jira Sync:** Periodically runs `gh pr list --state all` and `git log` to identify teammate/agent progress.
   - **Mapping & Transitions:** Maps features to Jira tickets and transitions them through all categories (**Backlog**, **Planning**, **Execution**, **Validation**, **Done**) based on Git/PR state.
   - Prompts The Planner to begin the next Epic.

## Agentic Guidelines
- **Strict FSM Architecture:** Agents must enforce a strict Finite State Machine (FSM) for game states at all times during the development phase (e.g., `STATE_DRAW_PHASE`, `STATE_WAITING_FOR_PEEK`, `STATE_INTERRUPT`). Avoid loose boolean flags (like `is_player_turn`) to control game logic, to prevent race conditions during interrupts like Jump-Ins.
- Treat yourself as an agent with foresight: proactively suggest follow-up tests, request missing assets, and double-check README rules before changing gameplay code.
- Use specialized AI tools as appropriate, but always keep descriptions and commits human-readable.
- Each commit/message must strictly follow the **Conventional Commits** format. Commits MUST include a short title (under 72 chars), a blank second line, and a descriptive body to ensure they render beautifully in GitHub. A `commit-msg` git hook and the `/commit` Antigravity workflow enforce this.
- When merging Pull Requests, always use **Squash and Merge** into `develop` or `epic/*` branches to keep the history linear. Direct merges to `main` should only occur for stable releases.
- **PR Formatting:** Pull Request descriptions and comments must use plain text ONLY. Avoid Markdown formatting (headers, bolding, lists) in GitHub as it may not render correctly in all environments.
- **Human + AI Pairing:** Each Human+AI pair owns an entire Epic (vertical slice) from start to finish. This eliminates synchronous dependencies (e.g., waiting on someone else to build the UI) and prevents merge conflicts.
- **Iterating on Completed Stories:** Agents are free to work on any Epic. However, stories marked as completed (`[x]`) in `user_stories.md` have already been verified and should be viewed with high regard. Any further changes to completed features should only be made to refine them with the best possible decisions or to address critical bugs, ensuring the core verified logic remains robust. Adding *new* stories (bullets) to an existing Epic is always encouraged.
- **Task Notation:** In `user_stories.md` and `task.md`, use `[ ]` for uncompleted, `[/]` for in-progress, and `[x]` for completed tasks.
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

## The Automation Loop
When instructed to "Start Epic X", the assistant must act as all 4 agents sequentially. The loop must be executed faithfully, with explicit announcements when switching roles:

1. **[The Planner]:** Read `README.md` and `user_stories.md`. Write `implementation_plan.md` outlining the architecture for the requested Epic. Pause and ask the User for approval.
2. **[The Executor]:** Wait for User approval. Once approved, write the code to implement the plan, strictly adhering to the FSM architecture. 
3. **[The Validator]:** Once the code is written, review the code and simulate edge cases from the `README.md`. Write a `walkthrough.md` documenting the results. If bugs are found, switch back to [The Executor] to fix them.
4. **[The Reviewer]:** Once validation passes, commit the code using Conventional Commits, update `user_stories.md` with `[x]` for completed tasks, and push to the branch.
