# Team Workload Split - Dutch Card Game

To avoid stepping on each other's toes and dealing with those murky merge conflicts, we'll split the project strictly by **Domain/Component**. Each person owns different scripts and scenes.

## Person 1: The UI & Game Board Architect
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

## Person 2: The Card Engineer (Data & Visuals)
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

---

## Person 3: The Game State Manager (The Brains)
**Goal:** Write the background logic that manages the rules, turns, and deck generation. This person shouldn't touch the UI scenes at all yet.
**Focus Files:** `game_manager.gd` (Autoload/Singleton), `deck_manager.gd`

**Tasks:**
1. Create a `game_manager.gd` script and add it to Project -> Settings -> Autoload.
2. Define the State Machine for the game flow: `DEAL_CARDS`, `PLAYER_TURN`, `CPU_TURN`, `CHECK_DUTCH`, `GAME_OVER`.
3. Create a `deck_manager.gd` script/class responsible for:
   - Generating a standard 52-card deck array.
   - Shuffling the array.
   - Handling `draw_card()` and `discard_card(card)` logic.
4. Setup signals in `game_manager.gd` like `signal turn_started(player_id)` and `signal game_over(winner_id)` that the UI will eventually listen to.

## Workflow Rules to Avoid Arguments
- **Never edit another person's scene.** If Person 3 needs the UI to do something, Person 3 fires a Signal, and Person 1 writes the code to listen to it.
- **Merge Order:** When the night is over, have Person 2 (Cards) merge first, then Person 3 (Logic), and finally Person 1 (UI) plugs the cards and logic into the board.
