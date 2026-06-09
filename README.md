# Dutch

Dutch is a rules-heavy card game of memory, strategy, and high-stakes social interaction. The goal is to finish with the lowest score, but with abilities, money, and "beers" at play, the path to victory is rarely straight.

## 🎴 The Basics
- **Setup**: Each player is dealt 4 cards face down. You may peek at any 2 at the start.
- **Turns**: Draw a card, decide to either **Discard** it or **Swap** it with one of your face-down cards.
- **Winning**: The player with the lowest score when the game ends wins. If you discard all your cards, you win immediately.

## 🍻 Penalty System (Beers)
Each player starts with **3 Beers**. Certain mistakes force you to "drink":
- **Failed Jump-In**: Trying to jump in with a card that doesn't match.
- **Instant Discard**: Drawing a card and immediately discarding it without swapping or using its ability (if applicable).
- **Elimination**: Once you drink all 3 beers, you pass out and are out of the game.

## 💰 Economy & Abilities
- **Money**: Discarding cards earns you money based on the card's value. 
    - **Aces**: High value.
    - **Kings of Spades, Hearts, Clubs**: Zero money.
- **The Chicken**: A 3D chicken hovers over the table. Click it to spend money and receive a golden **Ability Hammer** in your cabinet drawer.
- **Ability Hammers**: Kept in your player cabinet drawers (up to 6 slots). Hovering over a hammer shows its ability description, and clicking it (or pressing `E` when hovered) activates it on your turn. They don't clash with your hand cards.

### Standard Card Rules
- **Queen**: Look at any face-down card on the table (yours or an opponent's).
- **Jack**: Swap any two cards on the table.
- **King of Diamonds**: Counts as **0 points** (lowest possible value). Must be held in your hand to count toward your score.

### Special Ability Hammers
- **Bottoms Up**: Force a chosen player to drink a beer.
- **Refuel**: Receive an extra beer (max 3).
- **Trim Off**: Remove the highest card from your hand.
- **Boulder**: Give a chosen player the highest card presently in the deck.
- **Uno Reverse**: Reverse the playing order.
- **Skip**: Block a chosen player's turn.
- **Perfect Match**: Resets the game but you receive Ace, 2, 3, 4. Others get random cards; everyone keeps their money/abilities.
- **Inflation**: Double a player's card values (scoring only; original rank stays for Jump-Ins).
- **Half Off**: Halve a player's card values (scoring only).
- **Jumpscare**: Receive a card but choose a player to get jumpscared.
- **Shuffle**: Shuffle a player's cards.
- **Polarity Shift**: Invert the game's win condition (Highest Wins vs. Lowest Wins).

## ⚡ Special Moves
- **Jump-In**: If you have a card matching the last one discarded, play it at any time! 
    - **Success**: Hand size decreases.
    - **Failure**: Draw a penalty card and drink a beer.
- **Calling Dutch**: If you think you have the lowest score, call "Dutch". Everyone gets one last turn. You then **Confirm** to end or **Cancel** (forfeiting your right to call again).

## 🛠️ Developer Setup
- Run `git config core.hooksPath .githooks` after cloning.
- See [DESIGN.md](DESIGN.md) for technical architecture and FSM details.

## Local AI Agents (LM Studio)
The game can use the OpenAI-compatible LM Studio server for two separate agents:
- Chippy answers known rules instantly and uses the local model for ambiguous questions.
- Dutch Player Agent controls bot seat 1 through FSM-validated game tools.

Chippy also has a grounded catalog of the authored 3D scene, including the tavern, table, chairs, player drawers, ability hammers, cards, beers, chicken, avatars, indicators, HUD, and visual effects.

Setup:
1. Load `llama-3.2-1b-instruct` in LM Studio.
2. Start the Local Server on `http://127.0.0.1:1234`.
3. Launch the game normally. Both agents fall back to deterministic behavior if the server is unavailable.

The client sends `chat_template_kwargs.enable_thinking=false` by default to reduce move latency. Override the endpoint or model when needed:

```bash
export DUTCH_LM_STUDIO_URL=http://127.0.0.1:1234/v1
export DUTCH_LM_STUDIO_MODEL=llama-3.2-1b-instruct
```

Targeted verification:

For automated headless logic verification:
- On Windows: Run `run_qa.bat`
- To headlessly run individual test scripts (replace `<godot>` with your Godot 4 executable path/alias):
  ```bash
  <godot> --headless --path . --script res://verify_agent_tools.gd
  <godot> --headless --path . --script res://verify_lm_studio_client.gd
  ```

## 🌐 Multiplayer Testing
Multiplayer uses WebRTC via a public WebSocket signaling server (`wss://signal.maestriisigma.ro`).
- **Lobby Setup**: Enter a username, then choose to either host (generates a unique room code) or join (enter the host's room code).
- **Local Testing**: Run the PowerShell script `./run_two_instances.ps1` to launch two client windows side-by-side on your local machine.
