# Implementation Plan: 3D Board FSM Authority Pass

## Scope
Harden the gameplay state machine across:
- `game_manager.gd`
- `game_board_3d.gd`

Primary goal: make `GameManager` the sole authority for legal state transitions and human action permissions in the 3D board, with `game_board_3d.gd` acting as a thin consumer of that authority.

## Current Branch State
Completed in the first pass:
- `GameManager` now exposes manager-owned helpers for initial-peek completion and human pending-card interactivity.
- `game_board_3d.gd` now routes initial-peek completion through `GameManager.begin_initial_peek()` instead of calling `change_state()` directly.
- `game_board_3d.gd` now uses manager-backed legality checks for pending-card interactivity and the initial peek click path.
- Failed Jump-In elimination now attempts to restore the interrupted state instead of dropping the FSM on the floor.

Still open for validation:
- Verify the new helper-backed paths behave correctly in actual gameplay.
- Verify the failed Jump-In elimination branch resumes the interrupted state cleanly in every case.
- Verify the board no longer exposes illegal interaction windows during initial peek, Jump-In, and Dutch flows.

## Rule Anchors
- Cards stay face down except during legal draw, swap, peek, jump-in reveal, and end-game reveal flows.
- A turn is draw -> decide discard or swap -> resolve Queen/Jack if discarded -> end-turn or Dutch flow.
- Jump-In may only resolve against the last discarded card.
- Failed Jump-In keeps the attempted card and adds one unseen penalty draw.
- Dutch is callable on your turn, then resolves after one full rotation when that caller acts again.
- Scoring stays Ace=1 through King=13, with King of Diamonds = 0.

## Current Risks
- `GameManager.change_state()` has transition enforcement, but the transition graph still needs validation against all legal gameplay paths, especially interrupt resume paths.
- `game_board_3d.gd` still mixes board presentation with legality checks in several places, so the next slice should remove any remaining local assumptions.
- The initial deal still populates hands from the board side, so that flow should stay under review until validation proves it is safe.
- Failed Jump-In recovery on an eliminated jumper is now guarded, but it needs direct validation because it changes the interrupt-resume path.
- Human interaction affordances need to stay in sync with manager guards so the board never enables an illegal action window.

## Execution Plan

### 1. Finish `GameManager` as the FSM authority
- Validate and tighten the legal transition table for all normal and interrupt paths that the 3D board can reach.
- Keep one interrupt resume source of truth for Jump-In recovery.
- Ensure all public action methods are fully guard-backed:
  - `can_player_draw`
  - `can_player_discard_drawn_card`
  - `can_player_swap_drawn_card`
  - `can_player_start_jump_in`
  - `can_player_cancel_jump_in`
  - `can_player_select_jump_in_card`
  - `can_player_end_turn`
  - `can_player_call_dutch`
  - `can_player_confirm_dutch`
  - `can_player_cancel_dutch`
  - `can_player_use_peek_ability`
  - `can_player_select_swap_card`
  - board-facing aggregate helper(s) for human card interactivity
- Confirm that successful Jump-In always routes through one post-discard resolution path.
- Confirm that invalid Jump-In always resumes the interrupted state cleanly.

### 2. Align `game_board_3d.gd` to manager-owned permissions
- Replace any remaining direct state transitions with `GameManager` entry points.
- Gate deck/discard input, button visibility, card highlights, and card click dispatch through manager guards.
- Replace board-side legality composition with manager-backed helpers for pending cards and hand cards.
- Ensure Jump-In cancel vs end-turn semantics match the README rules and the current turn state.
- Keep animation and presentation in the board; keep legality in the manager.

## State-Transition Concerns To Verify
- `INITIALIZING -> DEAL_CARDS -> INITIAL_PEEK -> TURN_START_DRAW`
- `TURN_START_DRAW -> TURN_RESOLVE_DRAWN`
- `TURN_RESOLVE_DRAWN -> TURN_END_CHOICE`
- `TURN_RESOLVE_DRAWN -> TURN_PEEK_ABILITY`
- `TURN_RESOLVE_DRAWN -> TURN_SWAP_ABILITY`
- `TURN_END_CHOICE -> TURN_START_DRAW` on normal end turn
- `TURN_END_CHOICE -> TURN_JUMP_IN_SELECTION` on legal interrupt
- `TURN_START_DRAW -> TURN_JUMP_IN_SELECTION` on legal pre-draw interrupt
- `TURN_JUMP_IN_SELECTION -> interrupted state` on failed or cancelled Jump-In
- `TURN_JUMP_IN_SELECTION -> discard effect state` on successful Jump-In with Queen/Jack
- `TURN_JUMP_IN_SELECTION -> GAME_OVER` when the jumper empties their hand
- `TURN_END_CHOICE -> TURN_START_DRAW ... -> TURN_CONFIRM_DUTCH` across Dutch rotation
- `TURN_CONFIRM_DUTCH -> GAME_OVER` on confirm
- `TURN_CONFIRM_DUTCH -> TURN_START_DRAW` on cancel

## Assumptions To Preserve Or Re-evaluate
- Jump-In should resume the interrupted owner’s state, not invent a new end-of-turn state.
- A successful Jump-In during another player’s `TURN_START_DRAW` should return to that player’s draw opportunity unless README testing disproves it.
- Queen and Jack resolution after Jump-In should still be driven by the discarded card’s effect before resuming the interrupted state.
- Human interaction legality in the 3D board must match the manager exactly; presentation can still differ.
- Eliminated-player Jump-In failures should resume the interrupted state instead of leaving the match stranded.

## Verification Checklist
- Draw is only possible for the active player in `TURN_START_DRAW`.
- Discard/swap of the drawn card is only possible in `TURN_RESOLVE_DRAWN`.
- Queen can peek any face-down card and then returns to the correct next state.
- Jack can swap any two table cards and then returns to the correct next state.
- Human Jump-In button appears only in legal interrupt windows.
- Human cannot start Jump-In from unrelated states.
- Bot Jump-In only fires when the manager says it is legal.
- Failed Jump-In reproduces exact README behavior: attempted card stays, unseen penalty card added, interrupted turn resumes correctly.
- Successful Jump-In on a normal card resumes the interrupted state cleanly.
- Successful Jump-In on Queen/Jack resolves the effect and then resumes correctly.
- Failed Jump-In after beer elimination still resumes the interrupted state safely.
- Dutch can only be called by the active player during end choice.
- After Dutch is called, one full round completes before confirm/cancel appears.
- Confirm Dutch ends the game and reveals/scoring still follow README.
- Cancel Dutch returns play, disables that caller’s future Dutch calls, and does not break turn flow.
- 3D board input affordances only appear when `GameManager` allows them.

## Validator Handoff Notes
- Manual test focus: initial peek completion, Jump-In over end-turn, Jump-In before a draw, failed Jump-In elimination, Dutch full-rotation flow, empty-hand win path.
- Automated QA focus if Lead opts in: state legality, interrupt recovery, turn-owner continuity, draw/discard/swap exclusivity, Dutch progression, score calculation.
- If headless Godot still fails in this sandbox, rerun with the workspace-local `XDG_DATA_HOME` override before treating it as a gameplay failure.
