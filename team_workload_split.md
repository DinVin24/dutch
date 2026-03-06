# Team Workload Split - Dutch Card Game

To avoid stepping on each other's toes and dealing with those murky merge conflicts, we'll split the project strictly by **Domain/Component**. Each person owns different scripts and scenes.

## Person 1: aalex069 (The UI & Game Board Architect)
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

## Person 2: vlad (The Card Engineer - Data & Visuals)
**Tool:** ChatGPT Codex with GPT 5.1 mini
**Reason:** GPT 5.1 mini is fast and precise for creating straightforward, object-oriented scripts and tightly scoped classes like the Card data structures and state flip animations.
**Goal:** Create the core "Card" object that handles clicking, flipping, and data.
**Focus Files:** `card.tscn`, `card.gd`, `card_data.gd` (or Resource)

**Tasks:**
1. Create a `card_data.gd` Resource script that holds a card's underlying data (`suit`, `rank`, `point_value`).
    - *Tip:* Jack = 11, Queen = 12, King = 13, Red King = 0.
2. Build the `card.tscn` scene. It needs:
   - A `TextureRect` or `Sprite2D` for the front of the card.
   - A `TextureRect` or `Sprite2D` for the back of the card.
   - An `Area2D` (if 2D) or `TextureButton` to detect mouse clicks/hovers.
3. Write `card.gd` to handle flipping animations (tweening the scale to simulate a 3D flip) and emit signals when the card is clicked.

## Workflow Rules to Avoid Arguments
- **Never edit another person's scene.** Person 3's core logic is already implemented. If Person 1 or 2 needs UI/Card logic to interact with the game state, use the signals in the `GameManager` singleton.
- **Merge Order:** When the night is over, have Person 2 (Cards) merge first, and then finally Person 1 (UI) plugs the cards into the board and connects them to the `GameManager`.
