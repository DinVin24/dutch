# Task: 3D Board FSM Authority Pass

- [x] Realign `implementation_plan.md` so the slice only references `game_manager.gd` and `game_board_3d.gd`.
- [x] Create a concrete executor checklist for the current branch using `[ ]` / `[/]` / `[x]` notation.
- [x] Audit `game_board_3d.gd` for any remaining direct state transitions or local legality heuristics.
- [x] Add or refine `GameManager` helper methods needed by the 3D board for pending-card and hand-card interactivity.
- [x] Replace board-side legality composition in `game_board_3d.gd` with manager-backed permission checks.
- [/] Verify initial peek, Jump-In, Dutch confirm/cancel, and end-game reveal flows still match the README rules.
- [ ] Verify the eliminated-player failed Jump-In branch resumes the interrupted state instead of stranding the FSM.
- [ ] Verify the 3D board still blocks illegal interaction windows after the new helper-backed paths.
- [ ] Verify scoring and end-game reveal still match README values, including King of Diamonds = 0.
- [ ] Record any final validation findings in the handoff notes for the Executor/Validator pass.
