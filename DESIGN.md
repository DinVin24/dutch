# Design & Architecture

This document is Mermaid-first on purpose. Every fenced `mermaid` block below is intended to paste directly into `mermaid.live` without conversion.

## Full Match FSM

```mermaid
stateDiagram-v2
    [*] --> INITIALIZING
    INITIALIZING --> DEAL_CARDS: initialize_game()
    DEAL_CARDS --> INITIAL_PEEK: deal complete
    INITIAL_PEEK --> TURN_START_DRAW: all peeks complete

    TURN_START_DRAW --> TURN_RESOLVE_DRAWN: draw_card
    TURN_START_DRAW --> TURN_JUMP_IN_SELECTION: start_jump_in
    TURN_START_DRAW --> STATE_PLAYING_ABILITY: play_ability

    TURN_RESOLVE_DRAWN --> TURN_PEEK_ABILITY: discard Queen
    TURN_RESOLVE_DRAWN --> TURN_SWAP_ABILITY: discard Jack
    TURN_RESOLVE_DRAWN --> TURN_END_CHOICE: discard or swap normal card
    TURN_RESOLVE_DRAWN --> TURN_JUMP_IN_SELECTION: jump-in interrupt
    TURN_RESOLVE_DRAWN --> TURN_CONFIRM_DUTCH: resume to Dutch caller
    TURN_RESOLVE_DRAWN --> STATE_PLAYING_ABILITY: play_ability

    TURN_PEEK_ABILITY --> TURN_START_DRAW: jump-in consumed own draw
    TURN_PEEK_ABILITY --> TURN_END_CHOICE: complete_peek_ability
    TURN_PEEK_ABILITY --> TURN_CONFIRM_DUTCH: resume to Dutch caller
    TURN_PEEK_ABILITY --> STATE_PLAYING_ABILITY: cabinet ability

    TURN_SWAP_ABILITY --> TURN_START_DRAW: jump-in consumed own draw
    TURN_SWAP_ABILITY --> TURN_END_CHOICE: complete_swap_ability
    TURN_SWAP_ABILITY --> TURN_CONFIRM_DUTCH: resume to Dutch caller
    TURN_SWAP_ABILITY --> STATE_PLAYING_ABILITY: cabinet ability

    TURN_END_CHOICE --> TURN_START_DRAW: end_turn -> next_turn
    TURN_END_CHOICE --> TURN_JUMP_IN_SELECTION: start_jump_in
    TURN_END_CHOICE --> TURN_CONFIRM_DUTCH: caller ends final turn
    TURN_END_CHOICE --> STATE_PLAYING_ABILITY: play_ability

    TURN_JUMP_IN_SELECTION --> TURN_START_DRAW: cancel or resume draw phase
    TURN_JUMP_IN_SELECTION --> TURN_RESOLVE_DRAWN: resume drawn-card decision
    TURN_JUMP_IN_SELECTION --> TURN_END_CHOICE: resume normal turn end
    TURN_JUMP_IN_SELECTION --> TURN_PEEK_ABILITY: jump-in discarded Queen
    TURN_JUMP_IN_SELECTION --> TURN_SWAP_ABILITY: jump-in discarded Jack
    TURN_JUMP_IN_SELECTION --> GAME_OVER: jump-in emptied hand

    TURN_CONFIRM_DUTCH --> TURN_START_DRAW: cancel_dutch
    TURN_CONFIRM_DUTCH --> GAME_OVER: confirm_dutch

    STATE_PLAYING_ABILITY --> TURN_START_DRAW: resume_from_ability
    STATE_PLAYING_ABILITY --> TURN_RESOLVE_DRAWN: resume_from_ability
    STATE_PLAYING_ABILITY --> TURN_PEEK_ABILITY: resume_from_ability
    STATE_PLAYING_ABILITY --> TURN_SWAP_ABILITY: resume_from_ability
    STATE_PLAYING_ABILITY --> TURN_END_CHOICE: resume_from_ability
    STATE_PLAYING_ABILITY --> TURN_CONFIRM_DUTCH: resume_from_ability
    STATE_PLAYING_ABILITY --> INITIAL_PEEK: Perfect Match reset
    STATE_PLAYING_ABILITY --> GAME_OVER: elimination or terminal effect

    GAME_OVER --> DEAL_CARDS: restart or play again

    note right of GAME_OVER
        GameManager allows GAME_OVER from any in-progress state.
        That covers beer elimination, confirmed Dutch, jump-in victory,
        and disconnect timeout reducing the table to one active player.
    end note
```

`CHECK_DUTCH` still exists in the enum, but the live transition code currently routes straight into `TURN_CONFIRM_DUTCH`.

## Multiplayer Sequences

### Host-Authoritative Player Action And Sync

```mermaid
sequenceDiagram
    autonumber
    participant PlayerUI as Acting Player GameBoard3D
    participant HostGM as Host GameManager
    participant Support as DeckManager / AbilityManager
    participant HostBoard as Host GameBoard3D
    participant RemoteBoard as Remote Client GameBoard3D

    alt acting player is the host
        PlayerUI->>HostGM: request_action(action, args)
    else acting player is a client
        PlayerUI->>HostGM: request_action.rpc_id(1, action, args)
    end

    HostGM->>HostGM: validate sender seat + FSM gate

    alt draw_card
        HostGM->>Support: draw_card()
        HostGM->>HostGM: TURN_START_DRAW -> TURN_RESOLVE_DRAWN
        HostGM-->>HostBoard: turn_started + card_drawn_to_pending
    else discard_drawn or swap_drawn
        HostGM->>Support: mutate discard / hand / money / beers
        HostGM->>HostGM: resolve Queen, Jack, or TURN_END_CHOICE
        HostGM-->>HostBoard: discard + hand + state signals
    else play_ability
        HostGM->>HostGM: state_before_ability = current_state
        HostGM->>HostGM: TURN_* -> STATE_PLAYING_ABILITY
        HostGM->>Support: AbilityManager.execute(...)
        Support-->>HostGM: resume_from_ability() or state change
    else jump-in
        HostGM->>HostGM: save resume state
        HostGM->>HostGM: TURN_* -> TURN_JUMP_IN_SELECTION
        HostGM->>HostGM: validate rank match or fail with penalty
    end

    HostGM->>HostGM: _build_mp_sync_payload()
    HostGM-->>RemoteBoard: sync_match_state(payload) RPC
    RemoteBoard->>RemoteBoard: _apply_mp_sync_payload()
    RemoteBoard->>RemoteBoard: refresh board, prompts, HUD, seat view
```

### Disconnect Grace, Reconnect, And Timeout

```mermaid
sequenceDiagram
    autonumber
    participant Player as Dropped Player
    participant Signal as Signaling / WebRTC
    participant HostNet as Host NetworkManager
    participant HostGM as Host GameManager
    participant Others as Other Clients

    Player-xSignal: transport drops
    Signal-->>HostNet: peer_disconnected(peer_id)
    HostNet-->>HostGM: player_disconnected signal
    HostGM->>HostGM: _begin_peer_disconnect_grace(peer_id, player_idx)
    HostGM->>HostGM: clear peer mapping + start 15s deadline
    HostGM-->>Others: sync_match_state(disc_pending snapshot)
    Others->>Others: show "Holding seat for 15s"

    alt player rejoins before deadline
        Player->>Signal: join same room with same player name
        Signal-->>HostNet: new peer connected
        HostNet-->>HostGM: player_connected(peer_id, info)
        HostGM->>HostGM: find pending seat by player name
        HostGM->>HostGM: rebind peer_to_idx / idx_to_peer
        HostGM-->>Player: start_match.rpc_id(peer_id, num_players, 0)
        HostGM-->>Player: sync_match_state(current payload)
        HostGM-->>Others: sync_match_state(recovered payload)
        Others->>Others: show "reconnected"
    else timeout expires
        HostGM->>HostGM: _tick_pending_disconnect_grace()
        HostGM->>HostGM: _resolve_peer_disconnect_timeout()
        HostGM->>HostGM: mark player eliminated and bot
        alt timed-out seat had the active turn
            HostGM->>HostGM: clear pending drawn card if needed
            HostGM->>HostGM: next_turn()
        else timed-out seat was the jump-in actor
            HostGM->>HostGM: clear jump-in and resume saved state
        end
        HostGM-->>Others: sync_match_state(timeout payload)
        Others->>Others: show "timed out and was removed"
    end
```

### Play-Again Vote And Rematch Bootstrap

```mermaid
sequenceDiagram
    autonumber
    participant Human as Any Human Player
    participant HostNet as Host NetworkManager
    participant AllBoards as All GameBoard3D Scenes
    participant GM as GameManager

    Human->>HostNet: vote_play_again.rpc()
    HostNet->>HostNet: append unique voter
    HostNet->>HostNet: count non-bot humans in GameManager.players_info
    HostNet-->>AllBoards: update_play_again_status(voted, total)
    AllBoards->>AllBoards: update "Play Again (voted/total)"

    alt all humans voted
        HostNet->>HostNet: clear votes
        HostNet-->>AllBoards: start_match.rpc(total_players, new_seed)
        AllBoards->>GM: pending_mp_player_count = total
        AllBoards->>GM: pending_match_seed = new_seed
        AllBoards->>AllBoards: _on_network_game_started()
        AllBoards->>AllBoards: _reset_board_for_new_match()
        alt host board
            AllBoards->>GM: initialize_game(4)
        else client board
            AllBoards->>AllBoards: wait for fresh host sync payload
        end
    end
```

## Component Ownership

```mermaid
flowchart LR
    subgraph Entry["Entry / Shell"]
        MainMenu["MainMenu"]
        Lobby["Lobby"]
        SceneLoader["SceneLoader"]
        Settings["SettingsManager"]
        Responsive["ResponsiveUI"]
    end

    subgraph MatchScene["Local Match Scene"]
        Board["GameBoard3D"]
        Cards["Card3D / Cabinet3D / AbilityToken3D"]
        HUD["Action HUD / overlays / victory screens"]
        AssistantUI["AssistantOverlay"]
    end

    subgraph Authority["Authoritative Match Logic"]
        GM["GameManager"]
        Deck["DeckManager"]
        Ability["AbilityManager"]
    end

    subgraph Network["Multiplayer Transport"]
        Net["NetworkManager"]
        Signal["WebSocket signaling server"]
        RTC["WebRTCMultiplayerPeer"]
    end

    subgraph AI["Bots And Agent Tools"]
        Bots["BotController"]
        LlmBot["LlmPlayerAgent"]
        Tools["AgentToolRegistry"]
        Context["GameContext"]
        Knowledge["GameKnowledge / EnvironmentKnowledge"]
        LM["LmStudioClient"]
        Chippy["GameAssistant"]
    end

    MainMenu --> SceneLoader
    MainMenu --> Lobby
    Lobby --> Settings
    Lobby --> Responsive
    Lobby --> Net
    Lobby --> SceneLoader

    Board --> HUD
    Board --> Cards
    Board --> AssistantUI
    Board --> GM
    Board --> Net
    Board --> Bots
    Board --> LlmBot

    GM --> Deck
    GM --> Ability
    GM --> Net

    Net --> Signal
    Net --> RTC
    Net --> Lobby
    Net --> GM

    Bots --> GM
    LlmBot --> Tools
    Tools --> GM
    Tools --> Context
    Tools --> Knowledge
    LlmBot --> LM

    AssistantUI --> Chippy
    Chippy --> Knowledge
    Chippy --> LM
```

## Rule Interaction Matrix

### Core Special Cards And Turn-Flow Rules

```mermaid
flowchart TB
    subgraph Queen["Queen"]
        direction LR
        Q1["Trigger<br/>Discard Queen from draw or jump-in"] --> Q2["FSM<br/>TURN_RESOLVE_DRAWN or TURN_JUMP_IN_SELECTION -> TURN_PEEK_ABILITY"] --> Q3["Actor<br/>active_ability_player"] --> Q4["Effect<br/>Reveal any one face-down card"] --> Q5["Exit<br/>complete_peek_ability -> TURN_END_CHOICE, TURN_CONFIRM_DUTCH, or TURN_START_DRAW"]
    end

    subgraph Jack["Jack"]
        direction LR
        J1["Trigger<br/>Discard Jack from draw or jump-in"] --> J2["FSM<br/>TURN_RESOLVE_DRAWN or TURN_JUMP_IN_SELECTION -> TURN_SWAP_ABILITY"] --> J3["Actor<br/>active_ability_player"] --> J4["Effect<br/>Blindly swap any two valid hand slots"] --> J5["Exit<br/>complete_swap_ability -> TURN_END_CHOICE, TURN_CONFIRM_DUTCH, or TURN_START_DRAW"]
    end

    subgraph KingOfDiamonds["King Of Diamonds"]
        direction LR
        K1["Trigger<br/>Card exists in a hand or gets scored"] --> K2["Scoring rule<br/>point value is 0 instead of 13"] --> K3["Economy rule<br/>discarding it pays the top money tier"] --> K4["FSM<br/>no special state transition by itself"]
    end

    subgraph JumpIn["Jump-In"]
        direction LR
        I1["Trigger<br/>Any player sees matching discard rank"] --> I2["FSM<br/>interrupt into TURN_JUMP_IN_SELECTION"] --> I3["Validation<br/>selected rank must equal top discard rank"]
        I3 --> I4["Success<br/>remove card, discard it, gain money"]
        I3 --> I5["Failure<br/>drink beer, then draw penalty card after delay"]
        I4 --> I6["Exit<br/>resume saved state or GAME_OVER if hand emptied"]
        I5 --> I6
    end

    subgraph Dutch["Dutch"]
        direction LR
        D1["Trigger<br/>Current player presses Call Dutch in TURN_END_CHOICE"] --> D2["Effect<br/>set dutch_caller_index and pass turn"] --> D3["Table rule<br/>everyone gets one last normal turn"] --> D4["Caller re-enters TURN_CONFIRM_DUTCH after their final turn"] --> D5["Exit<br/>confirm -> GAME_OVER | forfeit -> TURN_START_DRAW and lose right to call again"]
    end
```

### Cabinet Ability Matrix

```mermaid
flowchart TB
    subgraph AbilityEnvelope["Shared Ability Envelope"]
        direction LR
        A0["Valid entry states<br/>TURN_START_DRAW, TURN_RESOLVE_DRAWN, TURN_END_CHOICE, TURN_PEEK_ABILITY, TURN_SWAP_ABILITY"] --> A1["play_ability()"] --> A2["FSM<br/>STATE_PLAYING_ABILITY"] --> A3["AbilityManager.execute(...)"] --> A4["Default exit<br/>resume_from_ability() back to saved state"]
    end

    subgraph PressureAndTempo["Pressure And Tempo"]
        direction TB
        BU1["Bottoms Up"] --> BU2["Target<br/>one player"] --> BU3["Effect<br/>target drinks 1 beer"]
        RF1["Refuel"] --> RF2["Target<br/>self"] --> RF3["Effect<br/>+1 beer, capped at 3"]
        SK1["Skip"] --> SK2["Target<br/>one player"] --> SK3["Effect<br/>target loses next turn"]
        RV1["Reverse"] --> RV2["Target<br/>table"] --> RV3["Effect<br/>flip turn_direction"]
    end

    subgraph HandAndDeckControl["Hand And Deck Control"]
        direction TB
        TR1["Trim Off"] --> TR2["Target<br/>self"] --> TR3["Effect<br/>discard highest-value known card"]
        BO1["Boulder"] --> BO2["Target<br/>one player"] --> BO3["Effect<br/>target receives highest-value card still in deck"]
        JS1["Jumpscare"] --> JS2["Target<br/>one player"] --> JS3["Effect<br/>target gains one drawn card"]
        SH1["Shuffle"] --> SH2["Target<br/>one player"] --> SH3["Effect<br/>randomize target hand order"]
    end

    subgraph ScoringControl["Scoring Control"]
        direction TB
        IN1["Inflation"] --> IN2["Target<br/>one player"] --> IN3["Effect<br/>target hand point modifiers x2"]
        HO1["Half Off"] --> HO2["Target<br/>one player"] --> HO3["Effect<br/>target hand point modifiers x0.5"]
        PS1["Polarity Shift"] --> PS2["Target<br/>table"] --> PS3["Effect<br/>toggle lowest-wins vs highest-wins"]
    end

    subgraph RoundReset["Round Reset"]
        direction TB
        PM1["Perfect Match"] --> PM2["Target<br/>whole round"] --> PM3["Effect<br/>collect all cards, reshuffle, give activator Ace+2+3+4, redeal others, restart INITIAL_PEEK"]
    end
```

## Wireframes

### Lobby Screen

```mermaid
flowchart LR
    subgraph LobbyScreen["Lobby.tscn"]
        direction LR

        subgraph LeftColumn["Left Column"]
            direction TB
            L1["Title"]
            L2["Name input"]
            L3["Room code input"]
            L4["Host button / Join button"]
            L5["Status / error label"]
            L6["Back button"]
        end

        subgraph RightColumn["Right Column"]
            direction TB
            R1["Room code + host IP"]
            R2["Players list"]
            R3["Match settings<br/>abilities / fill bots / beers / visibility"]
            R4["Start hint"]
            R5["Start match button"]
            R6["Copy room code button"]
        end
    end

    L4 -. host flow .-> R1
    L4 -. join flow .-> R2
    R3 -. host editable .-> R5
    R3 -. client read-only .-> R2
```

### In-Match HUD And 3D Board

```mermaid
flowchart TB
    subgraph MatchScreen["GameBoard3D"]
        direction TB

        subgraph TopBand["Top Band"]
            direction LR
            TL["Top-left<br/>turn label + local money"]
            TC["Top-center<br/>toast messages / Dutch alert / prompts"]
            TR["Top-right<br/>connection status / lag label"]
        end

        subgraph BoardSpace["Center 3D Space"]
            direction LR
            Seats["Four seat anchors<br/>avatars + player hands + cabinets"]
            Deck["Deck area"]
            Discard["Discard pile"]
            Targets["Player target areas"]
        end

        subgraph BottomBand["Bottom Band"]
            direction LR
            BL["Bottom-left action panel<br/>End Turn / Jump-In / Call Dutch / Confirm / Forfeit"]
            BR["Bottom-right utility stack<br/>ability description / help / emote"]
        end

        subgraph ModalLayer["Modal / transient overlays"]
            direction LR
            GO["Victory or elimination overlay<br/>scores + Play Again"]
            FX["Ability flashes / Dutch warning / Jumpscare"]
        end
    end

    TL --> BoardSpace
    TC --> BoardSpace
    TR --> BoardSpace
    BL --> BoardSpace
    BR --> BoardSpace
    BoardSpace --> GO
    BoardSpace --> FX
```

### Reconnect And Offline UX

```mermaid
flowchart TB
    subgraph ConnectionUX["In-match reconnect / offline wireframe"]
        direction TB

        subgraph PersistentFrame["Persistent frame"]
            direction LR
            P1["Board remains visible"]
            P2["Normal HUD stays mounted"]
            P3["Top-right connection badge<br/>OK / LAGGING / DISCONNECTED"]
        end

        subgraph GraceToast["Peer dropped but seat still reserved"]
            direction TB
            G1["Center-top toast<br/>'<name> disconnected. Holding seat for 15s.'"]
        end

        subgraph RecoveryToast["Peer recovered"]
            direction TB
            R1["Center-top toast<br/>'<name> reconnected.'"]
        end

        subgraph TimeoutToast["Peer timed out"]
            direction TB
            T1["Center-top toast<br/>'<name> timed out and was removed.'"]
        end

        subgraph HostDown["Host fully gone"]
            direction TB
            H1["Leave game()"]
            H2["Return to main menu scene"]
        end
    end

    P3 --> G1
    G1 --> R1
    G1 --> T1
    P3 --> H1 --> H2
```
