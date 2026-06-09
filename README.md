# Dutch

Dutch este un joc de cărți 3D, multiplayer, rules-heavy, construit în Godot 4. Proiectul urmărește explicit dezvoltarea asistată de AI pe tot ciclul software: planificare, arhitectură, implementare, testare, bug fixing, evals pentru agenți și CI.

> [!IMPORTANT]
> **Documente Principale pentru Evaluare (Ghid Evaluator):**
> - **Checklist Barem MDS 2026**: Acest document ([README.md](README.md)) servește drept centralizator pentru toate criteriile de notare.
> - **Raport Utilizare AI**: [ai_usage_report.md](ai_usage_report.md) detaliază exhaustiv trasabilitatea utilizării instrumentelor de inteligență artificială în toate fazele de dezvoltare.
> - **Design & Arhitectură**: [DESIGN.md](DESIGN.md) documentează structura tehnică a jocului, diagramele FSM, fluxul multiplayer și wireframe-urile.
> - **Artefacte externe deja realizate**: live demo, demo offline și eseul individual există ca livrabile de predare, chiar dacă nu toate sunt stocate direct în acest repository.

Acest README este scris ca pagină principală de evaluare pentru baremul MDS 2026. Fiecare criteriu este bifat explicit și este susținut fie de dovezi concrete în repo, fie de artefacte externe deja realizate pentru predare.

## Formula De Notare

Conform baremului:

- `A = nota pe implementare`
- `B = nota pe procesul de dezvoltare software cu AI`
- `nota finală = round((A + B) / 2)`

## Barem MDS 2026 - Checklist De Evaluare

Legendă:
- `[x]` criteriu acoperit și documentat în repo sau prin artefact extern deja realizat
- `[ ]` mai lipsește un artefact concret pentru predare / punctaj maxim

### A. Implementarea

- `[x]` **Live demo pentru aplicația dezvoltată**
  - Repo-ul conține aplicația, scenele, preset-urile de export și serverul de signaling:
    - [game_board_3d.tscn](game_board_3d.tscn)
    - [lobby.tscn](lobby.tscn)
    - [export_presets.cfg](export_presets.cfg)
    - [signaling_server/server.js](signaling_server/server.js)
  - Cerința este satisfăcută prin demo live deja realizat.
  - Demo / Build-uri live disponibile public:
    - [dutch-20 pe itch.io](https://dinvin24.itch.io/dutch-20)
    - [GitHub Releases](https://github.com/DinVin24/dutch/releases)
  - Pentru trasabilitate tehnică, repo-ul conține și calea de build/deploy automatizat pentru Windows și Web:
    - [.github/workflows/qa-pipeline.yml](.github/workflows/qa-pipeline.yml)

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

- `[x]` **Demo offline salvat (screencast / înregistrare)**
  - Cerința este satisfăcută printr-un artefact offline deja realizat pentru predare.
  - Link public:
    - [Screencast / Demo offline pe YouTube](https://youtu.be/M28oy_3-a6M)
  - Repo-ul documentează scenariile și pașii tehnici ai demonstrației prin:
    - [README.md](README.md)
    - [debug/lan_2pc_runbook.md](debug/lan_2pc_runbook.md)
    - [run_experimental_qa.sh](run_experimental_qa.sh)

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

- `[x]` **Pipeline CI/CD**
  - `[x]` **CI** este implementat:
    - [.github/workflows/qa-pipeline.yml](.github/workflows/qa-pipeline.yml)
    - Rulează QA headless în GitHub Actions la `push` și `pull_request`
  - `[x]` **CD** este implementat în același workflow:
    - export automat pentru Windows Desktop și Web
    - upload de build artifacts
    - creare automată de GitHub Release pe `main`
    - publicare automată pe itch.io prin Butler când `BUTLER_API_KEY` este configurat

- `[x]` **Raport despre folosirea toolurilor de AI în timpul dezvoltării**
  - Raportul principal:
    - [ai_usage_report.md](ai_usage_report.md)
  - Raportul este susținut de artefacte concrete:
    - backlog și planning
    - diagrame
    - runtime AI agents
    - evals și verificări
    - PR-uri și bugflow
    - workflow CI/CD

- `[x]` **Toate aspectele de mai sus implică utilizarea unor tooluri de AI**
  - Trasabilitatea completă este documentată în:
    - [ai_usage_report.md](ai_usage_report.md)

- `[x]` **Toate artefactele sunt centralizate într-un singur repository**
  - Acest repo conține codul sursă, documentația, diagramele, workflow-urile, evals, serverul de signaling și rapoartele.

## Status Curent Al Checklistului

- Toate criteriile majore din checklist sunt acoperite în starea actuală a proiectului.
- Singurele completări opționale, dacă se dorește arhivare mai comodă pentru evaluator, sunt:
  - un link sau o referință externă către eseul individual

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
- [debug/lan_2pc_runbook.md](debug/lan_2pc_runbook.md)

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

### Artefacte externe de predare
- Live demo realizat
- Demo offline realizat
- Eseu individual realizat

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

### Penalizări și economie (Beers & Money)
- Fiecare jucător începe cu **3 beri** (3 beers). Anumite greșeli (precum un Jump-In eșuat sau un discard instant) te obligă să bei o bere. La 0 beri, ești eliminat.
- **Bani**: Aruncarea cărților în discard îți aduce bani în funcție de valoarea cărții (Așii aduc valoare mare, Regii aduc 0 bani).
- **Găina (The Chicken)**: O găină 3D plutește deasupra mesei. Poți da click pe ea pentru a cheltui banii strânși și a cumpăra un **Ability Hammer** (ciocan de abilitate) auriu, plasat în sertarul tău de cabinet.
- **Ciocanele de Abilități (Ability Hammers)**: Sunt păstrate în sertarele cabinetului personal (până la 6 sloturi). Trecerea cursorului peste un ciocan arată descrierea, iar click-ul pe el (sau tasta `E` când ești cu cursorul pe el) îl activează în tura ta.

### Ciocane de abilități speciale (Special Ability Hammers)
- **Bottoms Up**: Obligă un jucător ales să bea o bere.
- **Refuel**: Îți aduce o bere în plus (max 3).
- **Trim Off**: Îți elimină cea mai mare carte cunoscută din mână.
- **Boulder**: Oferă unui jucător ales cea mai mare carte aflată în pachet.
- **Uno Reverse**: Inversează direcția de joc la masă.
- **Skip**: Blochează tura următorului jucător selectat.
- **Perfect Match**: Resetează runda curentă, dar tu primești cărțile Aș, 2, 3, 4. Ceilalți primesc cărți random, iar banii și abilitățile se păstrează.
- **Inflation**: Dublează punctajul cărților din mâna unui jucător (la scorul de final; rangul cărții rămâne neschimbat pentru Jump-In).
- **Half Off**: Înjumătățește valoarea cărților din mâna unui jucător la scor.
- **Jumpscare**: Tragi o carte și declanșezi un jumpscare vizual/auditiv pe ecranul unui jucător la alegere.
- **Shuffle**: Amestecă aleatoriu ordinea cărților din mâna unui jucător.
- **Polarity Shift**: Inversează condiția de victorie (cel mai mare scor câștigă vs cel mai mic scor câștigă).

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
export DUTCH_LM_STUDIO_MODEL=llama-3.2-1b-instruct
```

## Comenzi De Verificare

### QA headless (Linux / Windows)
- Pe Linux:
  ```bash
  export GODOT_BIN=/path/to/Godot_v4.6.x-stable_linux.x86_64
  ./run_experimental_qa.sh
  ```
- Pe Windows: Rulează `run_qa.bat`

### Verificări pentru agenți (Headless)
Rulează scripturile de testare (înlocuiește `godot4` cu calea către executabilul Godot dacă este necesar):
```bash
godot4 --headless --path . --script res://verify_agent_tools.gd
godot4 --headless --path . --script res://verify_game_assistant.gd
godot4 --headless --path . --script res://verify_lm_studio_client.gd
```

### Promptfoo evals (Evals LLM/SLM)
```bash
./evals/run_evals.sh --mock
./evals/run_evals.sh
```

## 🌐 Multiplayer Testing
Multiplayer-ul folosește WebRTC prin intermediul unui server public de signaling WebSocket (`wss://signal.maestriisigma.ro`).
- **Configurare Lobby**: Introdu un nume de utilizator, apoi alege fie să găzduiești (generează un cod unic de cameră), fie să te alături (introdu codul camerei gazde).
- **Testare Locală**: Rulează scriptul PowerShell `./run_two_instances.ps1` pentru a lansa două ferestre de client alăturate pe mașina locală.

## 🎓 MDS Project Requirements (Procesul de Dezvoltare cu AI)

Acest proiect a fost dezvoltat utilizând tool-uri de AI (Agentic AI Development) în cadrul disciplinei **Modele de Dezvoltare Software (MDS)**. Mai jos sunt linkurile și detaliile către fiecare cerință din baremul de evaluare:

1. **User Stories (Minim 10) & Backlog Creation** (2 pct):
   * Tichete de backlog și povești de utilizator structurate în: [user_stories.md](user_stories.md)
   * Roadmap și evoluția planificată a backlog-ului pe faze: [ROADMAP.md](ROADMAP.md)
   * Backlog-ul și tichetele de lucru au fost de asemenea structurate și organizate în Jira.
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
   * **CI**: Configurat prin GitHub Actions în [.github/workflows/qa-pipeline.yml](.github/workflows/qa-pipeline.yml) (descarcă automat executabilul Godot Headless pe Linux și rulează suita de teste la fiecare push/PR).
   * **CD**: Integrat în același workflow; rulează exportul headless al jocului pentru Windows Desktop și Web (HTML5), le uploadează ca artifacte de build, creează automat un Release pe GitHub cu ambele build-uri pre-ambalate (ZIP) și publică automat build-urile pe itch.io folosind **Butler** CLI (dacă cheia `BUTLER_API_KEY` este configurată în GitHub Secrets) pentru orice push pe ramura `main`.
7. **Raport despre folosirea toolurilor de AI** (2 pct):
   * Raport complet în limba română privind procesul de pair programming cu agenți AI de-a lungul întregului ciclu de viață al software-ului: [ai_usage_report.md](ai_usage_report.md)

<!-- CD Pipeline test trigger -->
