# 🇳🇱 Dutch: Strategic Roadmap

This roadmap outlines the evolution of the Dutch card game from its current 3D prototype to a polished, multiplayer-ready experience.

## 🎖️ Active Epic: Project Management & Governance
- **Current Goal**: Establish clear task assignment and documentation standards.
- **Assignee**: Project Manager (User)
- **Status**: [IN PROGRESS]

---

## 📅 PHASE 1: Visual & Audio Overhaul (Short-Term)
*Goal: Transform the "primitive" look into a thematic experience.*

### 🛠️ Tasks
1.  **Scene Rework**: Replace the current table/background with a "Run-down Bar" environment.
    - [ ] 3D Model: Bar Table with wood textures.
    - [ ] 3D Model: Realistic Beer bottles/mugs.
    - [ ] 3D Model: The Chicken (animated legs for interaction).
2.  **Card Aesthetics**:
    - [ ] Hand-painted textures for Ability Cards.
    - [ ] Multiplier visual markers on card faces (e.g., "x2" overlay).
3.  **UI/UX Optimization**:
    - [ ] Rework view angle for better board coverage.
    - [ ] Reduce UI saturation/bloat (cleaner headers and buttons).
    - [ ] **Easy Mode**: Optional toggle to keep player cards face-up.
4.  **Sound Design**:
    - [ ] Procedural sound effects for card flipping/drawing.
    - [ ] Ambient "Bar" background noise.

---

## 🌐 PHASE 2: Connectivity & Controls (Medium-Term)
*Goal: Enhance playability and technical stability.*

### 🛠️ Tasks
1.  **Input & Controls**:
    - [ ] Keybinds: `Space` (Jump-In), `Enter` (End Turn), `D` (Call Dutch), `C` (Confirm Dutch).
    - [ ] Controller support (Steam Deck/Gamepad).
2.  **Multiplayer Foundation**:
    - [ ] Refactor FSM for RPC-safe transitions.
    - [ ] Responsive Netcode (Godot Multiplayer API).
    - [ ] Browser (WebAssembly) support.
3.  **Advanced Gameplay**:
    - [ ] Implement all Ability Cards (Epic 8/15/16).
    - [ ] Economy System (Money/Chicken interaction).

---

## 🚀 PHASE 3: Social & Polishing (Long-Term)
*Goal: Community features and cross-platform release.*

### 🛠️ Tasks
1.  **Player Expression**:
    - [ ] Character Models (seated at the table).
    - [ ] Emote System (Winning/Losing animations).
    - [ ] In-game Voice Chat.
2.  **Platforms**:
    - [ ] Mobile (Android/iOS) UI adaptive layout.
3.  **Meta Progression**:
    - [ ] Profile stats and match history.
    - [ ] Ranked matchmaking.

---

## 🧑‍💼 Project Manager's Desk (Assignment Log)
*Programmers and AI agents should check this section for their active assignments.*

| Task ID | Component | Description | Assignee | Status |
| :--- | :--- | :--- | :--- | :--- |
| PM-001 | Docs | Merging redundant documentation | Antigravity | [COMPLETED] |
| VIS-001 | Assets | 3D Model: The Chicken | [UNASSIGNED] | [BACKLOG] |
| SYS-001 | Logic | Easy Mode Face-Up Toggle | [UNASSIGNED] | [BACKLOG] |

---

> [!TIP]
> **For AI Agents**: When taking a task from the roadmap, update the `Assignee` and `Status` columns in your first commit!
