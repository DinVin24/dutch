# AGENTS

## Mission
Ship the rules-heavy Dutch card game in Godot with a four-person crew that treats every instruction as an opportunity to leverage agentic AI (yourself included). Always keep the README.md rule set front and center: cards stay face down except on draws/swaps/jumps, point values are Ace=1 through King=13 (King of Diamonds = 0), and special moves like Jump-In, Queen, Jack, and the Dutch call govern turn flow and scoring.

## Roles & Responsibilities
1. **Arena Architect (Agent 1 / UI & Game Board)**
   - Build/maintain `game_board.tscn`, `game_board.gd`, and `player_ui.tscn` so the visual arena obeys README rules (places for deck/discard, four player zones, Dutch buttons, etc.).
   - Integrate signals from the GameManager singleton instead of touching Agent 2 or Agent 3 scenes directly.
2. **Card Engineer (Agent 2 / Card Data & Visuals)**
   - Own `card_data.gd`, `card.tscn`, and `card.gd`. Keep card values (Jack=11, Queen=12, King=13, King of Diamonds=0) consistent with the README scoring.
   - Provide crisp flipping visuals, click detection, and reusable data resources so Agent 3’s logic has a dependable card API.
3. **Game Flow Lead (Agent 3 / Turn & Rule Logic)**
   - Implement the turn cycle, Jump-In, special cards, Dutch calling, and scoring inside the GameManager singleton or scripts it owns.
   - Avoid editing Agent 1 or 2’s scenes; hook into their signals and cards through exported nodes and methods.
4. **QA / Pipeline (Agent 4 / Testing & Automation)**
   - Drive agentic test runs (Godot unit tests, input simulations) and documentation updates. Verify agent decisions with replayable test cases.

## Agentic Guidelines
- Treat yourself as an agent with foresight: proactively suggest follow-up tests, request missing assets, and double-check README rules before changing gameplay code.
- Use specialized AI tools (Gemini for layout, ChatGPT Codex for scripts) as noted in `team_workload_split.md`, but keep descriptions and commits human-readable.
- Each commit/message should describe how it advances the team’s shared goal, what signals/exports were touched, and how the rest of the crew should respond.
- Never change the git email and user name.

## Coordination
- Before editing a file owned by another role, confirm whether a dependency or signal hookup is required and note it in your update.
- Send status updates like “Card Engine: data resource now exposes suit/rank/points; awaiting Game Flow review” so the crew knows why the branch moved.
- Always run `git status` before and after major changes to avoid conflicts with the other agents.

## Verification & Handoff
- When a feature touches gameplay (Jump-In rules, scoring, ending the game), pair it with a short manual test plan or automated script that validates the README scenarios.
- Document any assumptions (e.g., “Jump-In triggered when discarded card matches without turn change”) so later agents can re-evaluate them.

## Safety Notes
- The “Google Antigravity” work you inherited is part of this repo’s narrative; treat it as a reference but not a requirement. When in doubt, follow the authoritative README and the team_workload_split ownership matrix.
- If a new team member or agent requests clarification, prefer a short question to avoid delivering the wrong implementation.
