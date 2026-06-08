# Design & Architecture

This document tracks the technical state of the Dutch card game, including the Finite State Machine (FSM), manager responsibilities, and scene hierarchy.

## 🏗️ Core Architecture
- **GameManager (Autoload)**: Owns the FSM and overall game flow. All state transitions happen here.
- **DeckManager (Autoload)**: Manages the deck and discard pile. Handles card creation and randomization.
- **NetworkManager (Autoload)**: Manages multiplayer WebRTC connections, lobbies, and client-server synchronization.
- **AgentToolRegistry**: Authoritative action validator and executor for AI agents.
- **LmStudioClient**: LLM client connecting the Godot engine to LM Studio.
- **LlmPlayerAgent**: Autonomous bot seat controller executing turns via tool calls.
- **GameAssistant (Chippy)**: Core rules assistant querying local knowledge (RAG) and refining language via LLM.

### 📊 Component Architecture Diagram
```mermaid
graph TD
    subgraph "Core Managers (Autoloads)"
        GM[GameManager] -->|Manages FSM| FSM[Finite State Machine]
        GM -->|Uses| DM[DeckManager]
        GM -->|Listens to| NM[NetworkManager]
    end

    subgraph "Visuals & UI"
        GB[GameBoard3D] -->|Listens to FSM| GM
        GB -->|Spawns| C3[Card3D]
        DC[DevConsole] -->|Debug State Overrides| GM
        AO[AssistantOverlay UI] -->|Queries| GA[GameAssistant]
    end

    subgraph "AI Agent System"
        GA -->|Checks CONFIDENCE| GK[GameKnowledge]
        GA -->|Checks SCENERY| EK[EnvironmentKnowledge]
        GA -->|Fallback / Refine| LM[LmStudioClient]
        
        LA[LlmPlayerAgent Bot] -->|Queries| LM
        LA -->|Requests actions| ATR[AgentToolRegistry]
        ATR -->|Queries context| GC[GameContext]
        ATR -->|Executes validated action| GM
        
        GC -->|Gathers snapshot| GM
    end
    
    subgraph "Multiplayer Networking"
        NM -->|Syncs state & RPCs| GM
        NM -->|Signaling & WebRTC| WS[Signaling Server]
    end
```

## 🔄 Finite State Machine (FSM)
Current States:
- `DEAL_CARDS`: Initial card distribution (4 cards per player).
- `INITIAL_PEEK`: Player selects 2 cards to see briefly.
- `TURN_START_DRAW`: Player draws from the deck.
- `TURN_RESOLVE_DRAWN`: Player decides to swap or discard the drawn card.
- `TURN_PEEK_ABILITY`: (Queen discarded) Reveal any card for 3s.
- `TURN_SWAP_ABILITY`: (Jack discarded) Swap any two cards on the board.
- `TURN_JUMP_IN_SELECTION`: Player is picking a card to match the pile.
- `TURN_CONFIRM_DUTCH`: The Dutch caller's final confirmation or forfeit.
- `TURN_END_CHOICE`: Player choices at end of turn (End, Jump, Call Dutch).
- `GAME_OVER`: Scoring, results UI, and potential restart.

### 🔄 FSM State Transition Diagram
```mermaid
stateDiagram-v2
    [*] --> INITIALIZING
    INITIALIZING --> DEAL_CARDS : Start game
    DEAL_CARDS --> INITIAL_PEEK : Cards dealt
    INITIAL_PEEK --> TURN_START_DRAW : Initial peeks complete
    
    TURN_START_DRAW --> TURN_RESOLVE_DRAWN : Player draws card
    TURN_START_DRAW --> STATE_PLAYING_ABILITY : Player triggers Ability Card
    
    TURN_RESOLVE_DRAWN --> TURN_PEEK_ABILITY : Queen discarded (Ability)
    TURN_RESOLVE_DRAWN --> TURN_SWAP_ABILITY : Jack discarded (Ability)
    TURN_RESOLVE_DRAWN --> STATE_PLAYING_ABILITY : Trigger Ability Card
    TURN_RESOLVE_DRAWN --> TURN_END_CHOICE : Card swapped / discarded
    
    TURN_PEEK_ABILITY --> TURN_END_CHOICE : Peek complete
    TURN_SWAP_ABILITY --> TURN_END_CHOICE : Swap complete
    
    TURN_END_CHOICE --> TURN_START_DRAW : End turn (normal flow)
    TURN_END_CHOICE --> TURN_CONFIRM_DUTCH : Call Dutch (under 7 points)
    TURN_END_CHOICE --> STATE_PLAYING_ABILITY : Trigger Ability Card
    
    %% Interrupt states (Jump-in)
    TURN_START_DRAW --> TURN_JUMP_IN_SELECTION : Any player initiates Jump-In
    TURN_RESOLVE_DRAWN --> TURN_JUMP_IN_SELECTION : Non-drawing player initiates Jump-In
    TURN_END_CHOICE --> TURN_JUMP_IN_SELECTION : Any player initiates Jump-In
    
    TURN_JUMP_IN_SELECTION --> GAME_OVER : Jump-in empties hand (instant win)
    TURN_JUMP_IN_SELECTION --> TURN_START_DRAW : Jump-in fails / completes (resume)
    TURN_JUMP_IN_SELECTION --> TURN_RESOLVE_DRAWN : Jump-in fails / completes (resume)
    TURN_JUMP_IN_SELECTION --> TURN_END_CHOICE : Jump-in fails / completes (resume)
    
    TURN_CONFIRM_DUTCH --> TURN_START_DRAW : Player forfeits Dutch (resume round)
    TURN_CONFIRM_DUTCH --> GAME_OVER : Player confirms Dutch (end round)
    
    STATE_PLAYING_ABILITY --> GAME_OVER : Ability triggers win/elimination
    STATE_PLAYING_ABILITY --> TURN_START_DRAW : Ability finishes (resume)
    STATE_PLAYING_ABILITY --> TURN_RESOLVE_DRAWN : Ability finishes (resume)
    STATE_PLAYING_ABILITY --> TURN_END_CHOICE : Ability finishes (resume)
    
    GAME_OVER --> DEAL_CARDS : Restart match
    GAME_OVER --> [*]
```

## 🃏 Card Data & Nodes
- **CardData (Resource)**: Stores rank, suit, and `is_face_up` visibility.
- **Card (Scene)**: Handles 3D/2D visual state, flip animations, and hover effects.

## 📋 Scenes
- `main_menu.tscn`: Game entry point.
- `game_board.tscn`: Main gameplay arena. Supports up to 4 players.
- `settings_menu.tscn`: Audio (Music/SFX) and Resolution settings.
- `pause_menu.tscn`: CanvasLayer overlay for match suspension.

## ⌨️ Debugging
- **Reveal All**: Press `L` to toggle visibility of all cards (visual only, doesn't change `CardData`).
- **Dev Console**: Integrated console for state manipulation and testing.
