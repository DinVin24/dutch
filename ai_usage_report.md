# Raport Exhaustiv De Utilizare A Toolurilor De AI

## Scopul Documentului

Acest document tratează explicit criteriul din baremul MDS 2026 referitor la:

- folosirea intensivă a toolurilor de AI în procesul de dezvoltare software
- documentarea clară a modului în care AI-ul a fost implicat
- existența unei trasabilități între activitățile asistate de AI și artefactele din repository

Raportul este intenționat concret și verificabil. Nu descrie doar „că am folosit AI”, ci arată:

1. **ce tooluri de AI au fost folosite**
2. **în ce etape ale dezvoltării**
3. **ce fișiere / PR-uri / teste au rezultat**
4. **cum a rămas omul în bucla de control și validare**

## Rezumat Executiv

Proiectul a fost construit în mod deliberat ca un exercițiu de **AI-assisted software engineering**. AI-ul nu a fost folosit punctual pentru completări izolate, ci ca infrastructură de lucru pe aproape toate palierele:

- backlog și planificare
- arhitectură și design
- implementarea logicii de joc
- implementarea networking-ului
- integrarea agenților AI în produs
- testare automată și evals
- bug triage și bug fixing
- CI
- documentație tehnică și handoff

În paralel, produsul final conține **doi agenți AI funcționali**:

- **Chippy / Game Assistant** - agent read-only pentru reguli și context
- **Dutch Player Agent** - agent autonom care joacă un seat de bot prin tool-uri validate de FSM

## Toolurile De AI Folosite

### 1. Codex / agent de coding asistat de LLM

Folosit pentru:

- analiză de cod existent
- propunere și implementare de modificări
- scriere și refactorizare de GDScript
- scriere de documentație tehnică
- generare și actualizare de diagrame Mermaid
- audit de bug-uri și corecții țintite
- operare Git/GitHub la nivel de branch, commit și PR

Artefacte asociate:

- [game_manager.gd](game_manager.gd)
- [network_manager.gd](network_manager.gd)
- [game_board_3d.gd](game_board_3d.gd)
- [DESIGN.md](DESIGN.md)
- [README.md](README.md)
- [ai_usage_report.md](ai_usage_report.md)

### 2. LM Studio

Folosit în două moduri distincte:

- **ca infrastructură de runtime** pentru agenții integrați în joc
- **ca infrastructură de evaluare live** pentru prompturi și comportamente agentice

Artefacte asociate:

- [lm_studio_client.gd](lm_studio_client.gd)
- [game_assistant.gd](game_assistant.gd)
- [llm_player_agent.gd](llm_player_agent.gd)
- [PROMPTFOO.md](PROMPTFOO.md)
- [evals/run_evals.sh](evals/run_evals.sh)

### 3. Promptfoo

Folosit pentru:

- evals reproducibile pentru agenții integrați în produs
- protecție împotriva regresiilor de prompt
- verificarea formatului de răspuns și a comportamentului pe cazuri reprezentative

Artefacte asociate:

- [PROMPTFOO.md](PROMPTFOO.md)
- [evals/chippy.yaml](evals/chippy.yaml)
- [evals/bot.yaml](evals/bot.yaml)
- [evals/mock_provider.py](evals/mock_provider.py)
- [evals/prompts/chippy_prompt.json](evals/prompts/chippy_prompt.json)
- [evals/prompts/bot_prompt.json](evals/prompts/bot_prompt.json)

### 4. Agenți AI integrați în produs

Acesta este un punct separat de „toolurile care scriu cod”. În aplicație există efectiv doi agenți AI.

- **Chippy**: explică reguli, contexte de joc și elemente ale mediului
- **Dutch Player Agent**: ia decizii de gameplay prin tool calls validate de registry și FSM

Artefacte asociate:

- [game_assistant.gd](game_assistant.gd)
- [assistant_overlay.gd](assistant_overlay.gd)
- [llm_player_agent.gd](llm_player_agent.gd)
- [agent_tool_registry.gd](agent_tool_registry.gd)
- [game_context.gd](game_context.gd)

## Acoperire Explicită A Baremului

Secțiunea aceasta există pentru a elimina ambiguitățile la evaluare. Pentru fiecare criteriu relevant, documentează:

- cum a fost folosit AI-ul
- ce artefacte verificabile există în repo
- care este statusul curent de predare

### A. Implementare

| Criteriu | Folosire AI | Dovezi | Status |
|---|---|---|---|
| Live demo | AI a asistat implementarea produsului demonstrabil, inclusiv gameplay, multiplayer, HUD și agenți | [game_board_3d.gd](game_board_3d.gd), [lobby.gd](lobby.gd), [network_manager.gd](network_manager.gd), [signaling_server/server.js](signaling_server/server.js) | În așteptarea linkului/rutei finale de prezentare |
| Minim 2 agenți AI în produs | AI-ul nu doar a asistat dezvoltarea, ci este parte a produsului final prin doi agenți runtime distincți | [game_assistant.gd](game_assistant.gd), [llm_player_agent.gd](llm_player_agent.gd), [project.godot](project.godot), [lm_studio_client.gd](lm_studio_client.gd) | Satisfăcut |
| Demo offline salvat | AI a asistat stabilizarea scenariilor demonstrabile și documentarea pașilor de verificare | [README.md](README.md), [run_experimental_qa.sh](run_experimental_qa.sh) | În așteptarea linkului către înregistrare |
| Temă originală | AI a fost folosit pentru a construi o aplicație de joc 3D rules-heavy, nu o aplicație web generică | [README.md](README.md), [game_manager.gd](game_manager.gd), [ability_manager.gd](ability_manager.gd) | Satisfăcut |

### B. Proces software cu AI

| Criteriu | Folosire AI | Dovezi | Status |
|---|---|---|---|
| User stories + backlog | AI pentru epics, stories, acceptance criteria și planning vertical slices | [user_stories.md](user_stories.md), [implementation_plan.md](implementation_plan.md), [AGENTS.md](AGENTS.md) | Satisfăcut |
| Diagrame | AI pentru FSM, sequence diagrams, ownership și wireframes Mermaid | [DESIGN.md](DESIGN.md) | Satisfăcut |
| Git / branches / PR-uri | AI pentru branch naming, conventional commits, PR drafting, handoff și iterare | [PR #47](https://github.com/DinVin24/dutch/pull/47), [PR #50](https://github.com/DinVin24/dutch/pull/50), [PR #58](https://github.com/DinVin24/dutch/pull/58), [PR #60](https://github.com/DinVin24/dutch/pull/60), [PR #61](https://github.com/DinVin24/dutch/pull/61) | Satisfăcut |
| Teste automate + evals | AI pentru QA headless, verificări țintite și evals Promptfoo pentru agenți | [qa_pipeline.gd](qa_pipeline.gd), [run_experimental_qa.sh](run_experimental_qa.sh), [PROMPTFOO.md](PROMPTFOO.md), [evals/chippy.yaml](evals/chippy.yaml), [evals/bot.yaml](evals/bot.yaml) | Satisfăcut |
| Bug report + PR fix | AI pentru diagnostic, localizare rapidă și patching țintit | [Issue #22](https://github.com/DinVin24/dutch/issues/22), [PR #58](https://github.com/DinVin24/dutch/pull/58) | Satisfăcut |
| CI/CD | AI pentru structurarea pipeline-ului CI și integrarea rulării headless; CD complet automatizat încă nefinalizat | [.github/workflows/qa-pipeline.yml](.github/workflows/qa-pipeline.yml), [run_experimental_qa.sh](run_experimental_qa.sh) | Parțial: CI da, CD încă de adăugat |
| Raport AI | AI pentru redactare, structurare și trasabilitate, cu verificare umană finală | [ai_usage_report.md](ai_usage_report.md), [README.md](README.md) | Satisfăcut |
| Toate artefactele implică AI și sunt în repo | AI implicat transversal în planning, cod, testare, bug fixing, doc și agenți runtime | [README.md](README.md), [ai_usage_report.md](ai_usage_report.md), [DESIGN.md](DESIGN.md), [PROMPTFOO.md](PROMPTFOO.md) | Satisfăcut |

## Metodologia Generală De Lucru Cu AI

Fluxul real de dezvoltare a fost:

1. **definirea unei intenții umane**
2. **analiza asistată de AI a codului și contextului**
3. **propunere sau implementare AI**
4. **verificare umană asupra logicii / UX / regulilor**
5. **testare automată**
6. **commit / PR / revizie**

Important: AI-ul a fost folosit agresiv, dar nu necontrolat. Autoritatea finală a rămas la nivel uman pentru:

- alegerea direcției produsului
- validarea regulilor față de README și backlog
- acceptarea modificărilor cu impact de gameplay
- acceptarea documentației finale pentru predare

## Trasabilitate Pe Etape Ale SDLC

### A. Planificare, backlog și structurarea muncii

AI-ul a fost folosit pentru:

- spargerea proiectului în epics și stories
- formularea acceptance criteria
- anticiparea dependențelor dintre FSM, UI, networking și gameplay
- redactarea planurilor de implementare pentru slice-uri verticale

Artefacte:

- [user_stories.md](user_stories.md)
- [implementation_plan.md](implementation_plan.md)
- [AGENTS.md](AGENTS.md)

Notă de trasabilitate:

- [implementation_plan.md](implementation_plan.md) este artefactul de planning inițial; unele detalii de networking au evoluat ulterior de la propunerea inițială la implementarea finală bazată pe WebRTC + signaling server. Acest lucru este normal într-un proces iterativ și păstrează tocmai istoricul deciziilor asistate de AI.

Rezultatul concret:

- backlog structurat cu mult peste minimul de 10 stories
- epics distincte pentru gameplay, multiplayer, tutorial, AI, QA și polish
- reguli clare de lucru pe roluri și pe faze

Validare umană:

- backlogul a fost revizuit și prezentat laborantului
- stories-urile implementate au fost marcate explicit în repo

### B. Arhitectură și design tehnic

AI-ul a fost folosit pentru:

- definirea responsabilităților pe manageri și scene
- explicarea limitelor de ownership între `GameManager`, `NetworkManager`, `GameBoard3D` și agenți
- modelarea FSM-ului și a sequence-diagram-urilor multiplayer
- descrierea UX pentru lobby, HUD și reconnect

Artefacte:

- [DESIGN.md](DESIGN.md)

Rezultatul concret:

- diagramă FSM completă
- sequence diagrams pentru sync, reconnect, timeout, play-again
- component ownership diagram
- rule interaction matrix
- wireframes Mermaid exportabile

Validare umană:

- diagramele au fost aliniate la codul curent, nu la schițe teoretice vechi

### C. Implementarea logicii de gameplay

AI-ul a fost folosit pentru:

- generarea și rafinarea logicii FSM
- validarea tranzițiilor legale între stări
- implementarea mecanicilor `draw`, `swap`, `discard`, `Dutch`, `Jump-In`, `Queen`, `Jack`
- integrarea economiei, beers și abilities

Artefacte principale:

- [game_manager.gd](game_manager.gd)
- [deck_manager.gd](deck_manager.gd)
- [ability_manager.gd](ability_manager.gd)
- [card_data.gd](card_data.gd)

Rezultatul concret:

- FSM strict și centralizat
- acțiuni validate server-side / authoritative
- scor, money, elimination, Dutch confirm/cancel, interrupt recovery

Validare umană:

- comparație cu regulile scrise în README
- verificări headless și smoke tests

### D. Implementarea UI, 3D și experiență de joc

AI-ul a fost folosit pentru:

- organizarea UI-ului în scene și overlay-uri
- integrarea HUD-ului și a feedback-ului contextual
- ajustări de cameră, seating, first-person alignment
- wireframe thinking pentru lobby, reconnect și overlay-uri

Artefacte principale:

- [game_board_3d.gd](game_board_3d.gd)
- [main_menu.gd](main_menu.gd)
- [lobby.gd](lobby.gd)
- [assistant_overlay.gd](assistant_overlay.gd)
- [tutorial_overlay.gd](tutorial_overlay.gd)

Rezultatul concret:

- lobby funcțional
- HUD pentru turn actions, Dutch, Jump-In, status multiplayer
- overlay-uri de tutorial, assistant, victory, elimination
- tratament explicit pentru reconnect și timeout

Validare umană:

- playtesting local
- ajustări iterative după feedback vizual

### E. Multiplayer și infrastructură de rețea

AI-ul a fost folosit pentru:

- proiectarea modelului host-authoritative
- sincronizarea stării către clienți
- refacerea logicii de mapping peer -> player slot
- gestionarea reconnect-ului și a timeout-ului de deconectare
- integrarea serverului de signaling

Artefacte principale:

- [network_manager.gd](network_manager.gd)
- [game_manager.gd](game_manager.gd)
- [lobby.gd](lobby.gd)
- [signaling_server/server.js](signaling_server/server.js)

Rezultatul concret:

- WebRTC multiplayer cu signaling WebSocket
- lobby host/join cu room code
- sync authoritative de match state
- `disconnect grace period`
- `play again` voting flow

Validare umană:

- teste manuale host/client
- corecții iterative pe camere, seat rotation, avatar facing și reconnect

PR-uri reprezentative:

- [PR #57](https://github.com/DinVin24/dutch/pull/57)
- [PR #60](https://github.com/DinVin24/dutch/pull/60)
- [PR #61](https://github.com/DinVin24/dutch/pull/61)

### F. Agenți AI integrați în aplicație

Acesta este unul dintre cele mai importante aspecte ale proiectului.

#### 1. Chippy / Game Assistant

AI-ul a fost folosit pentru:

- proiectarea comportamentului read-only
- grounding prin knowledge base local
- query pe contextul curent de joc
- fallback deterministic anti-hallucination
- polish prin LM Studio atunci când modelul local este disponibil

Artefacte:

- [game_assistant.gd](game_assistant.gd)
- [game_knowledge.gd](game_knowledge.gd)
- [environment_knowledge.gd](environment_knowledge.gd)
- [assistant_overlay.gd](assistant_overlay.gd)

Validări:

- [verify_game_assistant.gd](verify_game_assistant.gd)
- [evals/chippy.yaml](evals/chippy.yaml)

#### 2. Dutch Player Agent

AI-ul a fost folosit pentru:

- generarea modelului de agent autonom
- izolarea deciziilor în tool calls
- respectarea strictă a `allowed_actions`
- fallback deterministic când modelul nu răspunde sau nu este disponibil

Artefacte:

- [llm_player_agent.gd](llm_player_agent.gd)
- [agent_tool_registry.gd](agent_tool_registry.gd)
- [game_context.gd](game_context.gd)

Validări:

- [verify_agent_tools.gd](verify_agent_tools.gd)
- [evals/bot.yaml](evals/bot.yaml)

## Testare Automată Și Evals

AI-ul a fost implicat nu doar în scrierea codului, ci și în modul în care codul este testat.

### 1. QA headless pentru gameplay

Artefacte:

- [run_experimental_qa.sh](run_experimental_qa.sh)
- [qa_pipeline.gd](qa_pipeline.gd)

Ce verifică:

- initialization & deal
- turn rotation
- draw/discard
- draw/swap
- Queen
- Jack
- Dutch cycle
- Jump-In
- multiplayer sync payload logic

### 2. Verificări țintite

Artefacte:

- [verify_agent_tools.gd](verify_agent_tools.gd)
- [verify_game_assistant.gd](verify_game_assistant.gd)
- [verify_lm_studio_client.gd](verify_lm_studio_client.gd)
- [verify_tutorial_mode.gd](verify_tutorial_mode.gd)
- [verify_turn_pacing.gd](verify_turn_pacing.gd)
- [verify_emote_wheel.gd](verify_emote_wheel.gd)
- [verify_hand_layout_after_beer.gd](verify_hand_layout_after_beer.gd)

### 3. Evals pentru agenți prin Promptfoo

Artefacte:

- [PROMPTFOO.md](PROMPTFOO.md)
- [evals/chippy.yaml](evals/chippy.yaml)
- [evals/bot.yaml](evals/bot.yaml)
- [evals/run_evals.sh](evals/run_evals.sh)

Ce demonstrează:

- prompt regression testing
- structural compliance pentru tool-call style outputs
- grounding pe reguli și context
- comportament determinist în mock mode
- testare live în LM Studio mode

## Bug Reporting Și Bug Fixing Asistat De AI

AI-ul a fost folosit și în bucla de întreținere:

- triere a problemelor
- localizare rapidă în cod
- formulare de patch-uri țintite
- verificare post-fix
- actualizare de documentație și PR notes

### Exemplu concret verificabil

- Bug report:
  - [Issue #22](https://github.com/DinVin24/dutch/issues/22) - `Player cannot jump in on their own turn before drawing`
- Fix / rezolvare:
  - [PR #58](https://github.com/DinVin24/dutch/pull/58) - `fix(gameplay): resolve critical state locks and interaction bugs`

Acest tipar este important pentru barem, pentru că arată:

- raportare explicită a defectului
- reparare într-un branch separat
- integrare prin PR

## Git, PR-uri Și Colaborare Asistată De AI

AI-ul a fost folosit și pentru partea de lucru colaborativ, nu doar pentru cod:

- branch naming
- commit drafting în format conventional commits
- PR summaries
- documentarea schimbărilor
- pregătirea de handoff între etape

Artefacte și dovezi:

- [AGENTS.md](AGENTS.md)
- [PR #47](https://github.com/DinVin24/dutch/pull/47)
- [PR #50](https://github.com/DinVin24/dutch/pull/50)
- [PR #53](https://github.com/DinVin24/dutch/pull/53)
- [PR #58](https://github.com/DinVin24/dutch/pull/58)
- [PR #60](https://github.com/DinVin24/dutch/pull/60)
- [PR #61](https://github.com/DinVin24/dutch/pull/61)

În plus, istoricul local poate fi verificat cu:

```bash
git shortlog -sne --all
git log --oneline --decorate --graph --all
```

## CI Și DevOps

AI-ul a fost folosit pentru:

- structurarea pipeline-ului de QA în GitHub Actions
- configurarea rulării headless Godot
- automatizarea bootstrap-ului de verificare

Artefacte:

- [.github/workflows/qa-pipeline.yml](.github/workflows/qa-pipeline.yml)
- [run_experimental_qa.sh](run_experimental_qa.sh)

Status actual:

- **CI** este implementat și funcțional
- **CD** complet automatizat nu este încă finalizat

Acest lucru este important pentru onestitatea raportului: proiectul bifează clar partea de CI, iar partea de CD poate fi întărită în continuare pentru un maxim incontestabil pe criteriul „CI/CD”.

## Control Uman, Validare Și Limitări

Un proiect „AI-first” nu înseamnă proiect fără control.

În acest repo, omul a rămas responsabil pentru:

- definirea direcției produsului
- alegerea backlogului final
- validarea fidelității față de regulile jocului
- acceptarea sau respingerea patch-urilor generate cu ajutorul AI
- validarea finală a testelor și documentației

Limitări asumate și adresate în design:

- modelele locale pot halucina
- de aceea, agenții au fallback deterministic
- tool boundary-ul este validat strict prin `AgentToolRegistry`
- claims despre acțiuni legale sunt grounded în `GameContext` și `GameManager`

Artefacte relevante:

- [game_assistant.gd](game_assistant.gd)
- [agent_tool_registry.gd](agent_tool_registry.gd)
- [game_context.gd](game_context.gd)
- [verify_agent_tools.gd](verify_agent_tools.gd)

## Matrice Rezumat: Criteriu -> Dovezi

| Zonă | Cum a fost folosit AI | Dovezi |
|---|---|---|
| Backlog & planning | structurare stories, acceptance criteria, implementation planning | [user_stories.md](user_stories.md), [implementation_plan.md](implementation_plan.md), [AGENTS.md](AGENTS.md) |
| Arhitectură | FSM, ownership, multiplayer sequences, wireframes | [DESIGN.md](DESIGN.md) |
| Gameplay | implementare și rafinare logică rules-heavy | [game_manager.gd](game_manager.gd), [ability_manager.gd](ability_manager.gd), [deck_manager.gd](deck_manager.gd) |
| Multiplayer | host authority, sync, reconnect, timeout | [network_manager.gd](network_manager.gd), [signaling_server/server.js](signaling_server/server.js), [PR #60](https://github.com/DinVin24/dutch/pull/60) |
| Runtime AI | 2 agenți AI funcționali în produs | [game_assistant.gd](game_assistant.gd), [llm_player_agent.gd](llm_player_agent.gd) |
| Evals | testare sistematică a agenților | [PROMPTFOO.md](PROMPTFOO.md), [evals/chippy.yaml](evals/chippy.yaml), [evals/bot.yaml](evals/bot.yaml) |
| QA | headless pipeline și verificări țintite | [run_experimental_qa.sh](run_experimental_qa.sh), [qa_pipeline.gd](qa_pipeline.gd), [verify_game_assistant.gd](verify_game_assistant.gd) |
| Bug fixing | issue -> diagnostic -> PR fix | [Issue #22](https://github.com/DinVin24/dutch/issues/22), [PR #58](https://github.com/DinVin24/dutch/pull/58) |
| CI | rulare automată de QA în GitHub Actions | [.github/workflows/qa-pipeline.yml](.github/workflows/qa-pipeline.yml) |
| Documentație | README, raport AI, diagrame, handoff | [README.md](README.md), [ai_usage_report.md](ai_usage_report.md), [DESIGN.md](DESIGN.md) |

## Protocol Scurt De Verificare Pentru Evaluator

Dacă evaluatorul vrea o verificare rapidă, traseul minim este:

1. Deschide [README.md](README.md) pentru checklist-ul pe barem și statusul fiecărui criteriu.
2. Deschide [ai_usage_report.md](ai_usage_report.md) pentru trasabilitatea completă a folosirii AI.
3. Verifică existența celor doi agenți runtime în [project.godot](project.godot), [game_assistant.gd](game_assistant.gd) și [llm_player_agent.gd](llm_player_agent.gd).
4. Verifică evals și QA în [PROMPTFOO.md](PROMPTFOO.md), [evals/chippy.yaml](evals/chippy.yaml), [evals/bot.yaml](evals/bot.yaml), [qa_pipeline.gd](qa_pipeline.gd) și [.github/workflows/qa-pipeline.yml](.github/workflows/qa-pipeline.yml).
5. Verifică fluxul issue -> fix PR în [Issue #22](https://github.com/DinVin24/dutch/issues/22) și [PR #58](https://github.com/DinVin24/dutch/pull/58).
6. Verifică diagramele din [DESIGN.md](DESIGN.md) și backlogul din [user_stories.md](user_stories.md).

## Concluzie

În acest proiect, AI-ul a fost folosit:

- **ca accelerator de dezvoltare**
- **ca sursă de implementare**
- **ca infrastructură pentru agenți integrați în produs**
- **ca suport pentru QA, evaluare și documentare**

Raportat la baremul MDS 2026, utilizarea AI-ului este:

- largă ca suprafață
- vizibilă în artefactele din repo
- verificabilă prin cod, teste, PR-uri și documentație

Din acest motiv, criteriul „raport despre folosirea toolurilor de AI în timpul dezvoltării software” este documentat aici la un nivel potrivit pentru evaluare serioasă și pentru punctaj maxim, cu condiția ca și restul artefactelor finale de predare să fie atașate în repo.
