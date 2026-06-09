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

## 🎓 MDS Project Requirements (Procesul de Dezvoltare cu AI)

Acest proiect a fost dezvoltat utilizând tool-uri de AI (Agentic AI Development) în cadrul disciplinei **Modele de Dezvoltare Software (MDS)**. Mai jos sunt linkurile și detaliile către fiecare cerință din baremul de evaluare:

1. **User Stories (Minim 10) & Backlog Creation** (2 pct):
   * Tichete de backlog și povești de utilizator structurate în: [user_stories.md](user_stories.md)
   * Roadmap și evoluția planificată a backlog-ului pe faze: [ROADMAP.md](ROADMAP.md)
2. **Diagrame de Arhitectură și Workflow-uri** (1 pct):
   * Diagrame detaliate în format Mermaid (arhitectura componentelor, mașina de stări a jocului / FSM și fluxul de execuție al agenților): [DESIGN.md](DESIGN.md)
3. **Source Control cu Git** (1 pct):
   * Proiectul urmează standardul *Conventional Commits* (ex. `feat()`, `fix()`, `docs()`).
   * Istoricul de commits, ramurile create (ex. `docs/correct-hammers-and-multiplayer`, `fix/multiplayer-camera-timeout`) și fluxul de Pull Requests pot fi consultate în istoricul Git al repository-ului.
4. **Teste Automate și Evals pentru Agenți** (2 pct):
   * **Pipeline-ul local de testare (Headless)**: [qa_pipeline.gd](qa_pipeline.gd), care validează logic mașina de stări a jocului, rulat prin scriptul utilitar [run_qa.bat](run_qa.bat) (Windows) sau [run_experimental_qa.sh](run_experimental_qa.sh) (Linux).
   * **Teste funcționale / Smoke tests**: [verify_tutorial_mode.gd](verify_tutorial_mode.gd), [verify_chicken_purchase.gd](verify_chicken_purchase.gd) și [verify_agent_tools.gd](verify_agent_tools.gd).
   * **Agent Evals (Evaluări LLM/SLM)**: Fișierele de configurare și testare a performanței botului și asistentului (Chippy) în raport cu regulamentul: [evals/chippy.yaml](evals/chippy.yaml), [evals/bot.yaml](evals/bot.yaml), rulate prin scriptul [evals/run_evals.sh](evals/run_evals.sh).
5. **Raportare Bug și Rezolvare cu Pull Request** (1 pct):
   * Utilizarea de șabloane și rapoarte de corectură (ex. [pr_body.txt](pr_body.txt) și istoricul de PR-uri/issue-uri rezolvate direct de agenți).
6. **Pipeline CI/CD** (1 pct):
   * Configurat prin GitHub Actions în [.github/workflows/qa-pipeline.yml](.github/workflows/qa-pipeline.yml) (descarcă automat executabilul Godot Headless pe Linux și rulează suita de teste la fiecare push/PR).
7. **Raport despre folosirea toolurilor de AI** (2 pct):
   * Raport complet în limba română privind procesul de pair programming cu agenți AI de-a lungul întregului ciclu de viață al software-ului: [ai_usage_report.md](ai_usage_report.md)
