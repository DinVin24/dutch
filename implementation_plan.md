# Implementation Plan: Strict FSM Hardening

## Scope
Harden the gameplay state machine across:
- `game_manager.gd`
- `bot_controller.gd`
- `game_board.gd`
- `game_board_3d.gd`

Primary goal: make `GameManager` the sole authority for legal state transitions and player/bot action permissions, with boards and bots acting as thin consumers of that authority.

## Rule Anchors
- Cards stay face down except during legal draw, swap, peek, jump-in reveal, and end-game reveal flows.
- A turn is draw -> decide discard or swap -> resolve Queen/Jack if discarded -> end-turn or Dutch flow.
- Jump-In may only resolve against the last discarded card.
- Failed Jump-In keeps the attempted card and adds one unseen penalty draw.
- Dutch is callable on your turn, then resolves after one full rotation when that caller acts again.
- Scoring stays Ace=1 through King=13, with King of Diamonds = 0.

## Current Risks
- `GameManager.change_state()` now has transition enforcement, but the transition graph must be validated against all legal gameplay paths, especially interrupt resume paths.
- Jump-In resume logic has moved toward a single `jump_in_resume_state`, but it still needs full downstream consumption across UI and bot flows.
- `game_board.gd` and `game_board_3d.gd` still derive button visibility, card interactivity, and action legality from raw state fields instead of only asking `GameManager`.
- `game_board_3d.gd` is the furthest from strict FSM: it shows Jump-In from discard-pile heuristics, enables cards through local `block_cards` logic, and dispatches direct actions without manager-owned permission checks.
- `bot_controller.gd` has partially moved to guard helpers, but all action entry points and post-swap memory updates must align with confirmed manager outcomes.

## Execution Plan

### 1. Finish `GameManager` as the FSM authority
- Validate and tighten the legal transition table for all normal and interrupt paths.
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

### 2. Align `bot_controller.gd` to manager-owned permissions
- Remove direct FSM policy duplication where possible.
- Use manager guards before draw, resolve, Jump-In, Dutch, peek, swap, and confirm actions.
- Update Jack-memory bookkeeping only after a manager-confirmed swap result.
- Preserve bot decision policy while removing bot-owned legality assumptions.

### 3. Align `game_board.gd` to manager-owned permissions
- Replace UI-side turn/state checks in deck click, discard click, card click, Jump-In, Dutch, and end-turn handlers with manager guards.
- Replace button-visibility heuristics with guard-backed visibility.
- Replace card interactivity/highlighting logic with manager-driven per-card legality.
- Keep animation and presentation in the board; keep legality in the manager.

### 4. Align `game_board_3d.gd` to manager-owned permissions
- Remove local `block_cards` and discard-pile heuristics as the source of truth.
- Gate deck/discard input, button visibility, card highlights, and card click dispatch through manager guards.
- Ensure Jump-In cancel vs end-turn semantics match the 2D board and README rules.
- Ensure 3D board behavior matches 2D board behavior for all shared gameplay states.

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
- Human and bot interaction legality must be identical; only decision policy differs.

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
- Dutch can only be called by the active player during end choice.
- After Dutch is called, one full round completes before confirm/cancel appears.
- Confirm Dutch ends the game and reveals/scoring still follow README.
- Cancel Dutch returns play, disables that caller’s future Dutch calls, and does not break turn flow.
- 2D and 3D boards expose the same legal actions in the same states.

## Validator Handoff Notes
- Manual test focus: Jump-In over end-turn, Jump-In before a draw, Queen/Jack after Jump-In, Dutch full-rotation flow, empty-hand win path.
- Automated QA focus if Lead opts in: state legality, interrupt recovery, turn-owner continuity, draw/discard/swap exclusivity, Dutch progression, score calculation.
