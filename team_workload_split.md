# Team Workload Split - Dutch Card Game

To avoid stepping on each other's toes and dealing with those murky merge conflicts, we'll split the project strictly by **Domain/Component**. Each agent owns different scripts and scenes.

## Agent 1: Arena Architect (The UI & Game Board Architect)
**Tool:** Gemini
**Reason:** Gemini is great at drafting layout structures and understanding visual relationships, making it perfect for generating the Godot Control node trees and structural UI scripts. 
**Goal:** Build the visual arena where the game takes place.
**Focus Files:** `game_board.tscn`, `game_board.gd`, `player_ui.tscn`

**Tasks:**
1. Create `game_board.tscn` (the main game scene).
2. Layout the play area: 
   - A center area with placeholders for the Deck and the Discard Pile.
   - 2 to 4 player areas (bottom, top, left, right) with placeholders for 4 face-down cards each.
3. Build a reusable `player_ui.tscn` scene that represents a player's hand/status (avatar, score text, "Dutch" button).
4. Add basic animations/transitions for a card moving from the deck to the discard pile (just placeholders for now, the logic comes later).

---

## Agent 2: Card Engineer (Data & Visuals)
**Tool:** ChatGPT Codex with GPT 5.1 mini
**Reason:** GPT 5.1 mini is fast and precise for creating straightforward, object-oriented scripts and tightly scoped classes like the Card data structures and state flip animations.
**Goal:** Create the core “Card” object that handles clicking, flipping, and data.
**Focus Files:** `card.tscn`, `card.gd`, `card_data.gd` (or Resource)

**Tasks:**
1. Create a `card_data.gd` Resource script holding `suit`, `rank`, and derived `point_value`, enshrining Jack=11, Queen=12, King=13, and King of Diamonds = 0; include helpers for normalized display names so any UI reflects the rules.
2. Build `card.tscn` with a textured front/back setup plus a transparent `TextureButton` (or Area2D) so clicks only hit the card interaction area, and wire in label/icon nodes for suit/rank presentation.
3. Implement `card.gd` to consume the resource, update front/back visuals based on `is_face_up`, color the label/icon by suit, animate flips via tweens, and emit `card_clicked`/`card_flipped` so the GameManager can react.

## Workflow Rules to Avoid Arguments
- **Never edit another person's scene.** Person 3's core logic is already implemented. If Person 1 or 2 needs UI/Card logic to interact with the game state, use the signals in the `GameManager` singleton.
- **Merge Order:** When the night is over, have Person 2 (Cards) merge first, and then finally Person 1 (UI) plugs the cards into the board and connects them to the `GameManager`.
