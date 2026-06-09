# Dutch

Dutch este un joc de cărți 3D, multiplayer, rules-heavy, construit în Godot 4. Proiectul urmărește explicit dezvoltarea asistată de AI pe tot ciclul software: planificare, arhitectură, implementare, testare, bug fixing, evals pentru agenți și CI.

> [!IMPORTANT]
> **Documente Principale pentru Evaluare (Ghid Evaluator):**
> - **Checklist Barem MDS 2026**: Acest document ([README.md](README.md)) servește drept centralizator pentru toate criteriile de notare.
> - **Raport Utilizare AI**: [ai_usage_report.md](ai_usage_report.md) detaliază exhaustiv trasabilitatea utilizării instrumentelor de inteligență artificială în toate fazele de dezvoltare.
> - **Design & Arhitectură**: [DESIGN.md](DESIGN.md) documentează structura tehnică a jocului, diagramele FSM, fluxul multiplayer și wireframe-urile.

Acest README este scris ca pagină principală de evaluare pentru baremul MDS 2026. Fiecare criteriu este bifat explicit, are dovezi concrete în repo și notează separat ce mai rămâne de adăugat pentru punctaj maxim incontestabil.

## Formula De Notare

Conform baremului:

- `A = nota pe implementare`
- `B = nota pe procesul de dezvoltare software cu AI`
- `nota finală = round((A + B) / 2)`

## Barem MDS 2026 - Checklist De Evaluare

Legendă:
- `[x]` criteriu acoperit și documentat în repo
- `[ ]` mai lipsește un artefact concret pentru predare / punctaj maxim

### A. Implementarea

- `[ ]` **Live demo pentru aplicația dezvoltată**
  - Repo-ul conține aplicația, scenele, preset-urile de export și serverul de signaling:
    - [game_board_3d.tscn](game_board_3d.tscn)
    - [lobby.tscn](lobby.tscn)
    - [export_presets.cfg](export_presets.cfg)
    - [signaling_server/server.js](signaling_server/server.js)
  - Mai rămâne de adăugat:
    - `[ ]` link public către demo/build sau un scurt paragraf cu ruta exactă de prezentare live

- `[x]` **Minim 2 agenți AI integrați în produs**
  - **Chippy / Game Assistant**: agent read-only pentru reguli, context de joc și descrierea mediului
    - [game_assistant.gd](game_assistant.gd)
    - [assistant_overlay.gd](assistant_overlay.gd)
    - [game_knowledge.gd](game_knowledge.gd)
    - [environment_knowledge.gd](environment_knowledge.gd)
  - **Dutch Player Agent**: agent autonom care joacă un loc de bot prin tool calls validate de FSM
    - [llm_player_agent.gd](llm_player_agent.gd)
    - [agent_tool_registry.gd](agent_tool_registry.gd)
    - [game_context.gd](game_context.gd)
  - Integrarea lor în scenă:
    - [game_board_3d.gd](game_board_3d.gd)
  - Bootstrap-ul de runtime pentru tooluri și clientul local de model:
    - [project.godot](project.godot)
    - [lm_studio_client.gd](lm_studio_client.gd)

- `[ ]` **Demo offline salvat (screencast / înregistrare)**
  - Mai rămâne de adăugat:
    - `[ ]` link YouTube / Drive / altă arhivă către demo-ul offline

- `[x]` **Temă originală, diferită de proiectele clasice de web din semestrul 1**
  - Tema este un joc 3D de memorie, bluff, FSM strict, multiplayer și agenți AI locali, nu o aplicație web reutilizată din DAW.

### B. Procesul de dezvoltare software cu AI

- `[x]` **User stories (minim 10) + backlog creation**
  - Repo-ul conține un backlog mult peste pragul minim:
    - [user_stories.md](user_stories.md)
  - Include epics, stories și acceptance criteria pentru gameplay, multiplayer, tutorial, QA și AI.
  - Planning-ul slice-urilor verticale este documentat în:
    - [implementation_plan.md](implementation_plan.md)
  - Cerința de backlog este considerată satisfăcută și validată în prezentarea către laborant.
  - Notă:
    - `implementation_plan.md` este păstrat ca artefact de planning inițial; implementarea finală de multiplayer a evoluat către stack-ul WebRTC + signaling documentat în repo.

- `[x]` **Diagrame (UML / arhitectură / workflow-uri)**
  - Diagram set Mermaid exportabil:
    - [DESIGN.md](DESIGN.md)
  - Include:
    - FSM complet al meciului
    - sequence diagrams pentru sync, reconnect, timeout și play-again
    - component ownership
    - matrices pentru reguli și abilities
    - wireframes pentru lobby, HUD și stări de deconectare

- `[x]` **Source control cu git (branch creation, merge/rebase, PR-uri, minim 5 commits/student)**
  - Repo-ul are istoric extins de branch-uri și PR-uri merge-uite.
  - Exemple reprezentative:
    - [PR #47](https://github.com/DinVin24/dutch/pull/47) - evals pentru agenți
    - [PR #50](https://github.com/DinVin24/dutch/pull/50) - pipeline QA
    - [PR #53](https://github.com/DinVin24/dutch/pull/53) - raport AI
    - [PR #58](https://github.com/DinVin24/dutch/pull/58) - bugfix gameplay critic
    - [PR #60](https://github.com/DinVin24/dutch/pull/60) - multiplayer camera + disconnect grace
    - [PR #61](https://github.com/DinVin24/dutch/pull/61) - diagrame multiplayer/design
  - Verificare locală pentru commit volume:
    - `git shortlog -sne --all`
  - Conventional commits și disciplină de repo:
    - [AGENTS.md](AGENTS.md)

- `[x]` **Teste automate (inclusiv evals pentru agenți)**
  - QA headless pentru logica jocului:
    - [run_experimental_qa.sh](run_experimental_qa.sh)
    - [qa_pipeline.gd](qa_pipeline.gd)
  - Verificări țintite pentru gameplay și UI:
    - [verify_turn_pacing.gd](verify_turn_pacing.gd)
    - [verify_tutorial_mode.gd](verify_tutorial_mode.gd)
    - [verify_hand_layout_after_beer.gd](verify_hand_layout_after_beer.gd)
    - [verify_emote_wheel.gd](verify_emote_wheel.gd)
  - Evals pentru agenți:
    - [PROMPTFOO.md](PROMPTFOO.md)
    - [evals/chippy.yaml](evals/chippy.yaml)
    - [evals/bot.yaml](evals/bot.yaml)
    - [evals/run_evals.sh](evals/run_evals.sh)
    - [verify_agent_tools.gd](verify_agent_tools.gd)
    - [verify_game_assistant.gd](verify_game_assistant.gd)
    - [verify_lm_studio_client.gd](verify_lm_studio_client.gd)

- `[x]` **Raportare bug și rezolvare cu pull request**
  - Exemplu concret de bug report:
    - [Issue #22](https://github.com/DinVin24/dutch/issues/22) - player cannot jump in on own turn before drawing
  - Exemplu concret de bugfix prin PR:
    - [PR #58](https://github.com/DinVin24/dutch/pull/58) - rezolvă state locks și buguri de interacțiune
  - Alte issue-uri închise există în istoric și pot fi verificate în GitHub Issues.

- `[ ]` **Pipeline CI/CD**
  - `[x]` **CI** este implementat:
    - [.github/workflows/qa-pipeline.yml](.github/workflows/qa-pipeline.yml)
    - Rulează QA headless în GitHub Actions la `push` și `pull_request`
  - `[ ]` **CD** pentru punctaj maxim rămâne de întărit:
    - `[ ]` workflow automat pentru build/export artifact
    - `[ ]` opțional: release GitHub sau deploy documentat/automatizat

- `[x]` **Raport despre folosirea toolurilor de AI în timpul dezvoltării**
  - Raportul principal:
    - [ai_usage_report.md](ai_usage_report.md)
  - Raportul este susținut de artefacte concrete:
    - backlog și planning
    - diagrame
    - runtime AI agents
    - evals și verificări
    - PR-uri și bugflow
    - workflow CI

- `[x]` **Toate aspectele de mai sus implică utilizarea unor tooluri de AI**
  - Trasabilitatea completă este documentată în:
    - [ai_usage_report.md](ai_usage_report.md)

- `[x]` **Toate artefactele sunt centralizate într-un singur repository**
  - Acest repo conține codul sursă, documentația, diagramele, workflow-urile, evals, serverul de signaling și rapoartele.

## Ce Mai Rămâne De Bifat Concret

- `[ ]` Adăugare link către demo-ul offline când colegul îl urcă
- `[ ]` Adăugare link către live demo / build / mod exact de rulare pentru evaluare
- `[ ]` Adăugare workflow de CD pentru export/release automat, ca să nu rămână doar CI

## Hartă Rapidă A Artefactelor Din Repo

### Planning și backlog
- [user_stories.md](user_stories.md)
- [implementation_plan.md](implementation_plan.md)
- [AGENTS.md](AGENTS.md)

### Arhitectură și diagrame
- [DESIGN.md](DESIGN.md)
- [ROADMAP.md](ROADMAP.md)

### Logica de joc
- [game_manager.gd](game_manager.gd)
- [deck_manager.gd](deck_manager.gd)
- [ability_manager.gd](ability_manager.gd)
- [game_board_3d.gd](game_board_3d.gd)

### Multiplayer
- [network_manager.gd](network_manager.gd)
- [lobby.gd](lobby.gd)
- [signaling_server/server.js](signaling_server/server.js)

### Agenți AI integrați în joc
- [game_assistant.gd](game_assistant.gd)
- [assistant_overlay.gd](assistant_overlay.gd)
- [llm_player_agent.gd](llm_player_agent.gd)
- [agent_tool_registry.gd](agent_tool_registry.gd)
- [game_context.gd](game_context.gd)
- [lm_studio_client.gd](lm_studio_client.gd)

### Teste și evals
- [run_experimental_qa.sh](run_experimental_qa.sh)
- [qa_pipeline.gd](qa_pipeline.gd)
- [PROMPTFOO.md](PROMPTFOO.md)
- [evals/run_evals.sh](evals/run_evals.sh)
- [verify_agent_tools.gd](verify_agent_tools.gd)
- [verify_game_assistant.gd](verify_game_assistant.gd)

### CI
- [.github/workflows/qa-pipeline.yml](.github/workflows/qa-pipeline.yml)

### Raport AI
- [ai_usage_report.md](ai_usage_report.md)

## Descrierea Jocului

Dutch este un joc de memorie, risc și optimizare a scorului.

### Reguli de bază
- Fiecare jucător începe cu 4 cărți `face-down`
- La început poți privi 2 cărți
- În tură:
  - tragi o carte
  - apoi alegi fie să o arunci
  - fie să o schimbi cu una din mână
- Câștigă scorul cel mai mic
- Dacă rămâi fără cărți, câștigi imediat

### Scor
- `Ace = 1`
- `2 ... 10 = valoarea nominală`
- `Jack = 11`
- `Queen = 12`
- `King = 13`
- `King of Diamonds = 0`

### Reguli speciale
- **Queen**: privești orice carte `face-down`
- **Jack**: schimbi două cărți de pe masă
- **Jump-In**: poți juca în afara turei dacă ai același rang ca ultima carte din discard
- **Dutch**: anunți finalul rundei; toți ceilalți mai primesc un ultim tur, apoi confirmi sau renunți

### Penalizări și economie
- Fiecare jucător începe cu `3 beers`
- Greșelile costă beers
- Aruncarea cărților îți dă bani
- Banii se cheltuiesc pe abilities cumpărate de la chicken

## Setup Local

### Engine
- Godot `4.6.x`

### Rulare locală
```bash
godot4 --path .
```

### Multiplayer stack actual
- client/server logic în Godot
- WebRTC peer transport
- signaling WebSocket separat

Fișiere relevante:
- [network_manager.gd](network_manager.gd)
- [signaling_server/server.js](signaling_server/server.js)

### Server de signaling
```bash
cd signaling_server
npm install
npm start
```

## Agenți AI Locali

Proiectul folosește un server local compatibil OpenAI prin LM Studio pentru agenții integrați în gameplay.

### Chippy
- răspunde la întrebări despre reguli
- folosește knowledge base local și environment knowledge
- are fallback deterministic pentru a limita halucinațiile

### Dutch Player Agent
- controlează un bot seat
- alege acțiuni doar prin tool-uri validate de FSM
- nu poate sări peste regulile authoritative din `GameManager`

### Configurare LM Studio
1. Încarcă un model mic local în LM Studio
2. Pornește serverul local pe `http://127.0.0.1:1234`
3. Setează, dacă e nevoie:

```bash
export DUTCH_LM_STUDIO_URL=http://127.0.0.1:1234/v1
export DUTCH_LM_STUDIO_MODEL=qwen/qwen3.5-9b
```

## Comenzi De Verificare

### QA headless
```bash
export GODOT_BIN=/path/to/Godot_v4.6.x-stable_linux.x86_64
./run_experimental_qa.sh
```

### Verificări pentru agenți
```bash
godot4 --headless --path . --script res://verify_agent_tools.gd
godot4 --headless --path . --script res://verify_game_assistant.gd
godot4 --headless --path . --script res://verify_lm_studio_client.gd
```

### Promptfoo evals
```bash
./evals/run_evals.sh --mock
./evals/run_evals.sh
```
