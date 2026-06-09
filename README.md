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
- **The Chicken**: A 3D chicken hovers over the table. Click its legs to spend money and receive an **Ability Card**.
- **Ability Cards**: Kept face-down; view them once, then use them on your turn. They are a separate component and don't clash with your hand cards.

### Standard Card Rules
- **Queen**: Look at any face-down card on the table (yours or an opponent's).
- **Jack**: Swap any two cards on the table.
- **King of Diamonds**: Counts as **0 points** (lowest possible value). Must be held in your hand to count toward your score.

### Special Ability Tokens (Chicken Eggs)
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
1. Load `qwen/qwen3.5-9b` in LM Studio.
2. Start the Local Server on `http://127.0.0.1:1234`.
3. Launch the game normally. Both agents fall back to deterministic behavior if the server is unavailable.

The client sends `chat_template_kwargs.enable_thinking=false` by default to reduce move latency. Override the endpoint or model when needed:

```bash
export DUTCH_LM_STUDIO_URL=http://127.0.0.1:1234/v1
export DUTCH_LM_STUDIO_MODEL=qwen/qwen3.5-9b
```

Targeted verification:

```bash
godot4 --headless --path . --script res://verify_agent_tools.gd
godot4 --headless --path . --script res://verify_lm_studio_client.gd
```

## LAN Test Flow (Godot 4, ENet/UDP)
- LAN test flow uses ENet over UDP on port `1234`.
- Host listens on all interfaces; on Windows, allow inbound UDP `1234` for Godot/app in Defender Firewall.
- `localhost` remains supported for same-machine testing when no connect target is provided.

Host machine:
- `godot4 --path . -- --host`

Client machine (explicit host IP):
- `godot4 --path . -- --client --connect-to 192.168.1.42`

Client machine (same machine fallback):
- `godot4 --path . -- --client`

Auto handshake + commit helper script:
- Dry run only: `python lan_handshake_autocommit.py --host-ip 127.0.0.1 --dry-run`
- Run full flow (handshake, `git add .`, commit, push): `python lan_handshake_autocommit.py --host-ip 192.168.1.42`

---

## Deliverables (documentație proiect)

### Partea A

| Categorie | Fișier |
|-----------|--------|
| **Aplicație** | [project.godot](project.godot) — proiectul Godot (scenă principală, autoload-uri, configurare joc) |
| **Agenți AI** | [AGENTS.md](AGENTS.md) — workflow agentic; implementare: [game_assistant.gd](game_assistant.gd) (Chippy), [llm_player_agent.gd](llm_player_agent.gd) (Bot), [agent_tool_registry.gd](agent_tool_registry.gd) |

### Partea B

| Categorie | Fișier |
|-----------|--------|
| **User Stories** | [user_stories.md](user_stories.md) — epics și user stories (format Agile / Given-When-Then) |
| **Diagrame** | [DESIGN.md](DESIGN.md) — arhitectură, FSM și diagrame Mermaid |
| **Source Control** | [.githooks/commit-msg](.githooks/commit-msg) — hook Git pentru Conventional Commits |
| **Teste Automate** | [run_experimental_qa.sh](run_experimental_qa.sh) — pipeline QA headless (FSM, logică, integritate) |
| **Pull Requests** | [AGENTS.md](AGENTS.md#roles--responsibilities) — verificare PR, squash-merge, handoff între agenți |
| **CI/CD** | [.github/workflows/qa-pipeline.yml](.github/workflows/qa-pipeline.yml) — GitHub Actions: QA la push/PR pe `main` și `develop` |
| **AI Documentation** | [PROMPTFOO.md](PROMPTFOO.md) — evaluare prompturi Chippy/Bot; suite în [evals/](evals/) |
