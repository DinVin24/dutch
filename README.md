# Dutch 🃏

Dutch este un joc de cărți 3D, multiplayer, rules-heavy, construit în **Godot 4.6.x**. Proiectul urmărește în mod explicit dezvoltarea asistată de AI pe tot ciclul de viață al software-ului: planificare, design de arhitectură, implementare, testare automată, depanare, evaluări LLM (evals) și integrare continuă (CI/CD).

> [!IMPORTANT]
> **Documente principale și informații pentru Evaluare (Ghid Evaluator):**
> - **Membrii echipei**: Acest proiect a fost realizat de: **Preotesoiu Vlad**, **Simionov Teodora**, **Șoltuzu Emanuel**, **Telejman Alexandru** și **Vatavu Emilian**, toți de la **grupa 232**.
> - **Checklist Barem MDS 2026**: Acest document (`README.md`) centralizează toate criteriile de notare din barem.
> - **Raport Utilizare AI**: [ai_usage_report.md](ai_usage_report.md) detaliază exhaustiv trasabilitatea utilizării instrumentelor de inteligență artificială în toate fazele de dezvoltare.
> - **Design & Arhitectură**: [DESIGN.md](DESIGN.md) documentează structura tehnică a jocului, diagramele FSM (Finite State Machine), fluxul multiplayer WebRTC și wireframe-urile interfeței.
> - **Artefacte Externe Realizate**: Live demo, demo-ul offline și eseul individual reprezintă livrabile de predare finalizate, chiar dacă nu toate sunt stocate în mod direct în acest repository.

---

## 🎯 Formula De Notare (MDS 2026)

Conform regulamentului disciplinei Modele de Dezvoltare Software:
* $A$ = nota pe implementare (joc, multiplayer, agenți AI integrați, demo-uri)
* $B$ = nota pe procesul de dezvoltare software asistat de AI (backlog, diagrame, git, teste, CI/CD, raport)
* **Nota Finală** = $\text{round}\left(\frac{A + B}{2}\right)$

---

## 🎓 Barem MDS 2026 - Status Cerințe

### A. Implementarea (Nota A)

- `[x]` **Live demo pentru aplicația dezvoltată**
  - **Status**: Finalizat. Jocul, interfețele și serverul de signaling sunt complet implementate.
  - **Demo & Build-uri live disponibile public**:
    - 🌐 [dutch-20 pe itch.io](https://dinvin24.itch.io/dutch-20)
    - 📦 [GitHub Releases](https://github.com/DinVin24/dutch/releases)
  - **Fișiere relevante**: [game_board_3d.tscn](game_board_3d.tscn), [lobby.tscn](lobby.tscn), [export_presets.cfg](export_presets.cfg), [signaling_server/server.js](signaling_server/server.js).
  - **Deployment automat**: Pipeline-ul CI/CD rulează exportul automat pentru Windows și Web ([.github/workflows/qa-pipeline.yml](.github/workflows/qa-pipeline.yml)).

- `[x]` **Minim 2 agenți AI integrați în produs**
  - **Status**: Finalizat. Jocul include doi agenți AI locali distincti care rulează prin LLM local/LM Studio:
    1. **Chippy (Game Assistant)**: Agent de suport integrat în UI care răspunde la întrebări despre regulamentul jocului, starea mesei și comenzi folosind o bază de cunoștințe locală.
       - *Fișiere*: [game_assistant.gd](game_assistant.gd), [assistant_overlay.gd](assistant_overlay.gd), [game_knowledge.gd](game_knowledge.gd), [environment_knowledge.gd](environment_knowledge.gd)
    2. **Dutch Player Agent (Bot Seat)**: Agent autonom care controlează un loc de jucător la masă. Efectuează acțiuni (trage cărți, face swap, jump-in, folosește ciocane) prin tool calls, fiind constrâns de stările stricte din FSM.
       - *Fișiere*: [llm_player_agent.gd](llm_player_agent.gd), [agent_tool_registry.gd](agent_tool_registry.gd), [game_context.gd](game_context.gd)
    - *Integrare & Client*: [game_board_3d.gd](game_board_3d.gd), [lm_studio_client.gd](lm_studio_client.gd), [project.godot](project.godot).

- `[x]` **Demo offline salvat (screencast / înregistrare)**
  - **Status**: Finalizat.
  - **Link public**: 🎥 [Screencast / Demo offline pe YouTube](https://youtu.be/M28oy_3-a6M)
  - **Fișiere relevante**: [debug/lan_2pc_runbook.md](debug/lan_2pc_runbook.md), [run_experimental_qa.sh](run_experimental_qa.sh).

- `[x]` **Temă originală**
  - **Status**: Finalizat. Jocul Dutch 3D nu este o aplicație web clasică sau o reutilizare din semestrul 1. Este un joc de cărți complex, cu memorie, bluff, FSM strict, logică WebRTC multiplayer și agenți AI locali.

---

### B. Procesul de Dezvoltare Software cu AI (Nota B)

- `[x]` **User Stories (minim 10) & Backlog Creation**
  - **Status**: Finalizat. Backlog-ul este complet organizat în Jira și documentat în repo. Contine epics, stories și acceptance criteria pentru gameplay, multiplayer, tutorial, testare și AI.
  - **Fișiere relevante**: [user_stories.md](user_stories.md), [ROADMAP.md](ROADMAP.md), [implementation_plan.md](implementation_plan.md).

- `[x]` **Diagrame (UML / arhitectură / workflow-uri)**
  - **Status**: Finalizat. Documentația conține diagrame detaliate în format Mermaid.
  - **Conținut**: FSM-ul meciului, diagrame de secvență pentru sync, reconnect și play-again, matricea de abilități, structura componentelor și wireframe-uri HUD.
  - **Fișiere relevante**: [DESIGN.md](DESIGN.md).

- `[x]` **Source Control cu Git (branch creation, merge/rebase, PR-uri, minim 5 commits/student)**
  - **Status**: Finalizat. Echipa folosește standardul *Conventional Commits* și lucrează cu Pull Requests pe branch-uri de feature.
  - **Exemple PR-uri**: PR #47 (evals), PR #50 (pipeline QA), PR #53 (raport AI), PR #58 (corecturi gameplay), PR #60 (multiplayer & disconnect grace), PR #61 (diagrama de design).
  - **Ghid & Verificare**: [AGENTS.md](AGENTS.md) și comanda locală `git shortlog -sne --all`.

- `[x]` **Teste Automate și Evals pentru Agenți**
  - **Status**: Finalizat. Sistemul are o suită complexă de testare formată din:
    1. **Headless QA**: Validează logica jocului și a stărilor ([run_experimental_qa.sh](run_experimental_qa.sh), [qa_pipeline.gd](qa_pipeline.gd), [run_qa.bat](run_qa.bat)).
    2. **Smoke Tests / Verificări Funcționale**: [verify_turn_pacing.gd](verify_turn_pacing.gd), [verify_tutorial_mode.gd](verify_tutorial_mode.gd), [verify_hand_layout_after_beer.gd](verify_hand_layout_after_beer.gd), [verify_emote_wheel.gd](verify_emote_wheel.gd), [verify_chicken_purchase.gd](verify_chicken_purchase.gd).
    3. **Agent Evals (Promptfoo)**: Evaluări automate pentru calitatea răspunsurilor asistentului Chippy și ale botului conform regulilor ([PROMPTFOO.md](PROMPTFOO.md), [evals/chippy.yaml](evals/chippy.yaml), [evals/bot.yaml](evals/bot.yaml), [evals/run_evals.sh](evals/run_evals.sh), [verify_agent_tools.gd](verify_agent_tools.gd), [verify_game_assistant.gd](verify_game_assistant.gd)).

- `[x]` **Raportare Bug și Rezolvare cu Pull Request**
  - **Status**: Finalizat. Problemele sunt raportate prin GitHub Issues, iar rezolvările sunt verificate și adăugate prin PR-uri formale.
  - **Exemple**: [Issue #22](https://github.com/DinVin24/dutch/issues/22) (eroare la Jump-In în propria tură) rezolvat prin [PR #58](https://github.com/DinVin24/dutch/pull/58). Formatul rapoartelor folosește șablonul din [pr_body.txt](pr_body.txt).

- `[x]` **Pipeline CI/CD**
  - **Status**: Finalizat. Pipeline-ul rulează automat prin GitHub Actions la fiecare push sau PR.
  - **CI**: Execută suita de teste QA Headless pe Linux ([.github/workflows/qa-pipeline.yml](.github/workflows/qa-pipeline.yml)).
  - **CD**: Exportă automat executabilele pentru Windows Desktop, Web (HTML5) și Android, le încarcă ca artifacte, creează automat un GitHub Release pe ramura `main` și livrează build-urile direct pe itch.io folosind Butler.

- `[x]` **Raport despre utilizarea instrumentelor de AI**
  - **Status**: Finalizat. Raportul detaliază interacțiunea cu asistenții AI pe tot parcursul proiectului.
  - **Fișiere relevante**: [ai_usage_report.md](ai_usage_report.md).

- `[x]` **Toate aspectele implică AI & Centralizare în singur Repo**
  - **Status**: Finalizat. Toate livrabilele de mai sus se află în acest repository unic și au fost create în parteneriat Human-AI.

---

## 🃏 Descrierea Jocului & Regulament

Dutch este un joc de cărți axat pe memorie, risc și minimizarea scorului de la finalul rundei.

### 📋 Regulament de Bază
* Fiecare jucător începe cu **4 cărți așezate cu fața în jos** (face-down) în fața sa.
* La începutul meciului, ai voie să privești (peek) exact **2 cărți** din mâna ta.
* **Structura unui tur**:
  1. Tragi o carte din pachet (deck) sau din teancul de cărți aruncate (discard).
  2. Alegi fie să o arunci direct în discard, fie să o schimbi (swap) cu una dintre cărțile tale (fără a o privi pe cea pe care o înlocuiești, dacă nu o cunoști deja).
* **Scopul**: Să obții cel mai mic scor total la finalul rundei. Dacă rămâi fără cărți în mână, câștigi instant.

### 🔢 Sistemul de Punctaj
* **As (Ace)** = 1 punct
* **2 - 10** = Valoarea nominală a cărții
* **Valet (Jack)** = 11 puncte
* **Damă (Queen)** = 12 puncte
* **Popă (King)** = 13 puncte
* **Popă de Caro (King of Diamonds ♦️)** = **0 puncte** (Cea mai valoroasă carte din joc!)

### ⚡ Reguli Speciale (Abilitățile Cărților din Discard)
Când arunci anumite cărți de joc în teancul de discard, declanșezi acțiuni speciale:
* **Dama (Queen)**: Îți permite să privești (peek) orice carte cu fața în jos de pe masă.
* **Valet (Jack)**: Îți permite să schimbi (swap) între ele oricare două cărți de pe masă (ale tale sau ale adversarilor), fără a le privi.
* **Jump-In (Intrare prin Intercepție)**: Dacă un jucător aruncă o carte în discard, orice alt jucător (inclusiv în afara turei sale) poate arunca rapid o carte identică ca rang din mâna sa. Dacă este corect, își micșorează mâna. Dacă greșește, primește o carte de penalizare și bea o bere.
* **Dutch**: Un jucător poate striga **"Dutch!"** în tura sa dacă consideră că are cel mai mic scor. Toți ceilalți jucători mai primesc un singur tur final, după care se calculează scorurile.

### 🍺 Economia Jocului (Beers & Money)
* **Beri (Beers)**: Fiecare jucător începe cu **3 beri**. Greșelile majore (ex: Jump-In greșit sau discard instant eronat) te obligă să bei o bere. La 0 beri rămase, ești eliminat din meci.
* **Bani ($)**: Când arunci cărți în discard, primești bani în funcție de valoarea cărții (Așii aduc cei mai mulți bani, Regii aduc 0$).
* **Găina (The Chicken)**: O găină 3D plutește deasupra mesei. Jucătorii pot da click pe ea pentru a cheltui banii strânși și a cumpăra un **Ciocan de Abilități (Ability Hammer)**.

### 🔨 Sertarul de Abilități (Ability Hammers)
Ciocanele cumpărate sunt plasate în cabinetul personal (maximum 6 sloturi). Trecerea cursorului peste un ciocan îi arată descrierea, iar click-ul (sau tasta `E`) îl activează în tura ta:
* **Bottoms Up**: Obligă un adversar la alegere să bea o bere.
* **Refuel**: Îți aduce o bere înapoi (maximum 3).
* **Trim Off**: Îți elimină cea mai mare carte cunoscută din mână.
* **Boulder**: Trimite cea mai mare carte din pachet unui adversar ales.
* **Uno Reverse**: Schimbă sensul de joc la masă.
* **Skip**: Blochează tura următorului jucător selectat.
* **Perfect Match**: Resetează runda actuală. Tu primești cărțile As, 2, 3, 4. Ceilalți primesc cărți aleatorii, însă banii și abilitățile se păstrează.
* **Inflation**: Dublează valoarea finală a cărților unui jucător ales la scor.
* **Half Off**: Înjumătățește valoarea finală a cărților unui jucător ales la scor.
* **Jumpscare**: Declanșează un jumpscare vizual/auditiv pe ecranul unui adversar ales.
* **Shuffle**: Re-amestecă aleatoriu ordinea cărților din mâna unui jucător.
* **Polarity Shift**: Inversează condiția de victorie (cel mai mare scor câștigă runda).

---

## 🛠️ Ghid de Instalare, Rulare și Testare

### 1. Cerințe Preliminare
* **Godot Engine**: Versiunea **4.6.x** (recomandat 4.6.1 sau 4.6.2).
* **Node.js**: Versiunea LTS (pentru serverul de signaling).

### 2. Rulare Locală
Pentru a porni jocul în mod normal:
1. Pornirea serverului de signaling:
   ```bash
   cd signaling_server
   npm install
   npm start
   ```
2. Deschiderea proiectului în Godot:
   ```bash
   godot4 --path .
   ```
   *(Înlocuiește `godot4` cu calea către executabilul tău Godot dacă nu este în PATH)*

### 3. Testare Multiplayer Locală
Pentru a testa conexiunea WebRTC direct pe aceeași mașină:
* În Windows, folosește scriptul PowerShell inclus:
  ```powershell
  ./run_two_instances.ps1
  ```
  Acesta va lansa automat două instanțe ale jocului pentru a testa interacțiunea în rețea.
* Alternativ, introduceți un nume în Lobby, creați o cameră pe o instanță, copiați codul și alăturați-vă din a doua instanță. Implicit, jocul se conectează la serverul public de signaling `wss://dutch-signaling.onrender.com`.

### 4. Rulare QA Headless (Suita de Teste Logică)
* **Linux**:
  ```bash
  export GODOT_BIN=/cale/catre/Godot_v4.6.x
  ./run_experimental_qa.sh
  ```
* **Windows**:
  Rulează fișierul batch preconfigurat:
  ```cmd
  run_qa.bat
  ```

---

## 🤖 Configurare Agenți AI (LM Studio)

Jocul folosește un server local compatibil cu API-ul OpenAI (ex: LM Studio) pentru a rula agenții autonomi la masă.

### Pași Configurare:
1. Pornirea serverului în LM Studio pe portul implicit `127.0.0.1:1234`.
2. Încărcarea unui model instruct compact (de exemplu, `llama-3.2-1b-instruct` sau similar).
3. Configurarea variabilelor de mediu (opțional, dacă diferă de setările implicite):
   ```bash
   export DUTCH_LM_STUDIO_URL="http://127.0.0.1:1234/v1"
   export DUTCH_LM_STUDIO_MODEL="llama-3.2-1b-instruct"
   ```

### Testarea Headless a Agenților:
Poți rula separat scripturile de validare a integrării AI din linia de comandă:
```bash
godot4 --headless --path . --script res://verify_agent_tools.gd
godot4 --headless --path . --script res://verify_game_assistant.gd
godot4 --headless --path . --script res://verify_lm_studio_client.gd
```

### Rularea Evaluărilor (Promptfoo Evals):
Pentru a rula framework-ul de testare al comportamentului LLM-urilor:
* Rulare cu server mock (recomandat pentru CI/CD rapid):
  ```bash
  ./evals/run_evals.sh --mock
  ```
* Rulare cu LLM real:
  ```bash
  ./evals/run_evals.sh
  ```

---

## 📂 Harta Artefactelor Importante

Pentru o navigare rapidă în structura proiectului:

* **Documentație & Organizare**:
  * [user_stories.md](user_stories.md) - Poveștile de utilizator și criteriile de acceptare.
  * [DESIGN.md](DESIGN.md) - Structura claselor, diagramele FSM și diagramele de secvență.
  * [ROADMAP.md](ROADMAP.md) - Etapele de dezvoltare ale proiectului.
  * [ai_usage_report.md](ai_usage_report.md) - Raportul detaliat privind interacțiunea cu AI.
  * [AGENTS.md](AGENTS.md) - Regulile de dezvoltare și rolurile echipei.
* **Componente Nucleu Godot (Scripts)**:
  * [game_manager.gd](game_manager.gd) - Managerul central de stări și logica autoritativă.
  * [deck_manager.gd](deck_manager.gd) - Gestionarea pachetului de cărți și a teancului de discard.
  * [ability_manager.gd](ability_manager.gd) - Logica pentru ciocane și abilități speciale.
  * [network_manager.gd](network_manager.gd) - Configurația WebRTC și sync-ul stărilor în multiplayer.
* **Integrare AI & Evals**:
  * [game_assistant.gd](game_assistant.gd) / [assistant_overlay.gd](assistant_overlay.gd) - Logica asistentului Chippy.
  * [llm_player_agent.gd](llm_player_agent.gd) / [agent_tool_registry.gd](agent_tool_registry.gd) - Logica botului autonom.
  * [evals/chippy.yaml](evals/chippy.yaml) / [evals/bot.yaml](evals/bot.yaml) - Teste Promptfoo de evaluare a comportamentului.
* **Suita de Testare & Teste**:
  * [qa_pipeline.gd](qa_pipeline.gd) - Pipeline-ul principal headless de QA.
  * [verify_tutorial_mode.gd](verify_tutorial_mode.gd) / [verify_hand_layout_after_beer.gd](verify_hand_layout_after_beer.gd) - Teste de UI/integrare.
  * [debug/lan_2pc_runbook.md](debug/lan_2pc_runbook.md) - Ghid tehnic de testare multiplayer în rețeaua locală.
* **Artefacte Externe de Predare**:
  * Live demo realizat (itch.io)
  * Demo offline realizat (YouTube)
  * Eseu individual realizat
