# Dutch - Agile User Stories (Restructured)

## Epic 1: Core Game Board & Arena [KAN-61]
- [x] **Story**: As a player, I want to see a clear distinction between the deck, the discard pile, and all four player zones, so that I instantly understand the flow of cards. [KAN-14]
  * **Acceptance Criteria**:
    * **Given** a new game is started
    * **When** the arena loads
    * **Then** the deck, discard pile, and 4 player zones are distinctly separated and visible.
- [x] **Story**: As a player, I want cards to be instantiated face down by default but easily flipped when the rules permit, so that the hidden-information mechanics of the game are preserved. [KAN-15]
  * **Acceptance Criteria**:
    * **Given** cards are dealt to players
    * **When** a player receives their initial hand
    * **Then** all cards are face down and cannot be seen until an action explicitly flips them.
- [x] **Story**: As a player, I want the game board layout to respond gracefully to UI scaling and window resizing, so that the card positioning remains clean and legible. [KAN-16]
  * **Acceptance Criteria**:
    * **Given** the game window is open
    * **When** the user resizes the window or changes resolution
    * **Then** the UI containers dynamically resize without overlapping or breaking the layout.

## Epic 2: Turn Cycle & Basic Moves [KAN-62]
- [x] **Story**: As a player, I want to be required to draw a card from the deck at the start of my turn before doing anything else, so that the game enforces the primary rule. [KAN-20]
  * **Acceptance Criteria**:
    * **Given** it is the beginning of a player's turn
    * **When** the player attempts to discard or swap without drawing
    * **Then** the action is blocked, and they are forced to draw first.
- [x] **Story**: As a player, I want to be able to drag the card I just drew directly to the discard pile if it's too high value (e.g. King), so that my turn ends immediately without penalty. [KAN-21]
  * **Acceptance Criteria**:
    * **Given** the player just drew a card from the deck
    * **When** they drag it to the discard pile
    * **Then** the card is discarded, and their turn immediately ends.
- [x] **Story**: As a player, I want to be able to drag the card I just drew onto one of my face-down cards to swap them, dropping my old face-down card into the discard pile automatically, so that I can improve my score. [KAN-22]
  * **Acceptance Criteria**:
    * **Given** the player has drawn a card
    * **When** they drop it onto one of their face-down cards
    * **Then** the drawn card takes its place, and the old face-down card is moved to the discard pile face-up.

## Epic 3: Special Card Mechanics [KAN-63]
- [x] **Story**: As a player, when I discard a Queen, I want the UI to highlight all players' cards and allow me to click exactly one to secretly peek at it, so that I can gain information. [KAN-23]
  * **Acceptance Criteria**:
    * **Given** a player discards a Queen
    * **When** the Queen effect triggers
    * **Then** the player can select one card on the board to secretly peek at, then their turn ends.
- [x] **Story**: As a player, when I discard a Jack, I want the game to prompt me to select two cards on the board to swap their places (without flipping them), so that I can strategize without breaking the hidden-information rule. [KAN-24]
  * **Acceptance Criteria**:
    * **Given** a player discards a Jack
    * **When** the Jack effect triggers
    * **Then** two chosen cards blindly swap positions on the board without revealing their faces.

## Epic 4: The Jump-In System [KAN-64]
- [x] **Story**: As a player, I want the game to allow me to drag one of my cards to the discard pile at any point (even if it's not my turn) to attempt a Jump-In. [KAN-37]
  * **Acceptance Criteria**:
    * **Given** another player's turn is active
    * **When** I click and drag a card to the discard pile
    * **Then** the game evaluates it as a Jump-In attempt.
- [x] **Story**: As a player, if my Jump-In card matches the rank of the current top discard card, I want the game to accept the discard while maintaining the original turn order, so that I am rewarded for my memory without disrupting the game flow. [KAN-38]
  * **Acceptance Criteria**:
    * **Given** a card is dragged for a Jump-In
    * **When** its rank perfectly matches the discard pile's top card
    * **Then** the card is successfully discarded, and the current turn owner's turn resumes.
- [x] **Story**: As a player, if my Jump-In card does not match the current top discard card, I want my card returned to its original position and the game to automatically deal me an extra penalty card, so that guessing is discouraged. [KAN-39]
  * **Acceptance Criteria**:
    * **Given** a card is dragged for a Jump-In
    * **When** its rank does not match the top discard card
    * **Then** the card returns to the player's zone and the player receives an extra penalty card.

## Epic 5: End Game & Scoring [KAN-65]
- [x] **Story**: As a player, I want a "Call Dutch" button available during my turn that signals the final round, so that I can attempt to end the game when I believe I have the lowest score. [KAN-40]
  * **Acceptance Criteria**:
    * **Given** it is the player's turn
    * **When** they click "Call Dutch"
    * **Then** a final round triggers for all other players before ending the game.
- [x] **Story**: As a player, once my "Dutch" call cycles back to my turn, I want to be prompted to either confirm the call (ending the game) or cancel it (forfeiting my right to call Dutch again for the rest of the game). [KAN-41]
  * **Acceptance Criteria**:
    * **Given** the round completes after a "Dutch" call
    * **When** it cycles back to the original caller
    * **Then** they must rigidly confirm or cancel the call.
- [x] **Story**: As a player, when the game ends, I want all cards flipped face up and the points tallied according to the rules (Ace=1, ..., King of Diamonds=0), so that the lowest scorer is immediately declared the winner. [KAN-42]
  * **Acceptance Criteria**:
    * **Given** the game ends
    * **When** scoring initiates
    * **Then** all cards flip, point values are summed (excluding King of Diamonds which is 0), and a winner is declared.

## Epic 6: AI Opponents (Bots) [KAN-66]
- [x] **Story**: As a system, I want the bot to have a simulated "memory" of cards it has peeked at, so that it can make rational decisions. [KAN-31]
- [x] **Story**: As a system, I want the bot to strategically evaluate the card it draws from the deck and appropriately discard unknown cards for low-value drawn cards. [KAN-32]
- [x] **Story**: As a system, I want the bot to purposefully use its Queen and Jack abilities strategically (peeking at opponents or swapping worst/best cards) when available. [KAN-33]
- [x] **Story**: As a system, I want the bot to recognize when an opponent discards a matching card, and automatically trigger a "Jump In". [KAN-34]

## Epic 7: Visual Overhaul & Aesthetics [KAN-35]
- [x] **Story**: As a player, I want the game environment to feel dark and suspenseful with focused spotlights on the table and volumetric fog. [KAN-43]
  * **Acceptance Criteria**:
    * **Given** the game is played
    * **When** rendering the 3D scene
    * **Then** dynamic spotlights and fog create a tense atmosphere.
- [x] **Story**: As a player, I want to see CRT scanlines, chromatic aberration, and digital glitch effects (Y2K aesthetic), so that the game feels like a piece of retro-tech. [KAN-44]
- [x] **Story**: As a player, I want the UI to use high-saturation neons and glassmorphism contrasting with the dark 3D scene. [KAN-45]
- [x] **Story**: As a player, I want every card move, swap, and draw to have "juice" (screen shake, card wobble, subtle particle trails). [KAN-46]

## Epic 8: The Tavern Expansion [KAN-36]
- [x] **Story**: As a player, I want 3 physical 3D beers spawned at my side, representing lives, which I must drink from if I fail a Jump-In or instantly discard a drawn card. [KAN-47]
- [x] **Story**: As a player, I want to earn money scaled to the rank of discarded cards to create an economic layer. [KAN-48]
- [x] **Story**: As a player, I want to click a hovering chicken to spend money and spawn an egg that cracks into a face-down Ability Card. [KAN-49]
- [x] **Story**: As a player, I want to be able to use a variety of disruption and utility abilities (Shuffle, Reverse, Skip, Boulder, etc.).

## Epic 9: Online Multiplayer Matchmaking [KAN-25]
- [ ] **Story**: As a player, I want to find matches online quickly using a matchmaking system.
- [ ] **Story**: As a player, I want to host private lobbies to play with my friends.

## Epic 10: Cosmetic Unlock System [KAN-50]
- [ ] **Story**: As a player, I want to earn experience points from matches to unlock new card backs and character skins.


## Epic 11: Voice Chat Integration [KAN-53]
- [ ] **Story**: As a player, I want spatial voice chat in the tavern to interact with other players during matches.

## Epic 12: Polarity Shift (Advanced Mechanics) [KAN-67]
- [x] **Story**: As a player, I want to be able to use a 'Polarity Shift' ability to invert the game's win condition between Lowest Wins and Highest Wins. [KAN-69]
  * **Acceptance Criteria**:
    * **Given** a Polarity Shift ability is played
    * **When** the effect triggers
    * **Then** the win condition flips, and the final scoring reflects the new goal (Lowest or Highest score).

## Epic 13: Quality of Life, Analytics & Accessibility [KAN-72]
- [x] **Story**: As a player who struggles with memory, I want an "Easy Mode" toggle that keeps my cards face-up at all times, so that I can focus on strategy rather than memorization.
- [x] **Story**: As a player, I want a standardized keybinding system (Jump-In, End Turn, Dutch, Forfeit, Choosing cards) so that I can play efficiently without a mouse.
- [x] **Story**: As a player, I want my volume, resolution, and keybind settings saved persistently so I don't have to reconfigure them every launch.
- [ ] **Story**: As a persistent winner, I want my "Matches Won" stat saved to my profile so I can flex on my enemies.

## Epic 14: The Immersive Tavern (Roadmap Phase 2) [KAN-73]
- [x] **Story**: As a player, I want to feel the atmosphere of a "Run-down Bar" with thematic table, chairs, and surroundings.
- [ ] **Story**: As a player, I want to see the 3D Chicken animated and reacting to my purchases.
- [ ] **Story**: As a player, I want to see 3D Beer mugs that visually empty as I drink them for penalties.

## Epic 15: Social & Multiplayer (Roadmap Phase 3 & 4) [KAN-74]
- [ ] **Story**: As a player, I want to host or join a multiplayer room from a lobby list and pick my own username.
- [ ] **Story**: As a winner, I want to trigger a unique emote animation and celebrate in spatial voice chat.

## Epic 16: Interactive Tutorial Mode [KAN-76]
- [x] **Story**: As a first-time player, I want a Tutorial option on the main menu start screen (alongside Normal/Easy), so that I can opt into a guided experience without reading a manual. [KAN-77]
  * **Acceptance Criteria**:
    * **Given** I click START_FILE
    * **When** the difficulty prompt appears
    * **Then** a TUTORIAL button is visible alongside Normal and Easy
    * **When** I click TUTORIAL
    * **Then** the game loads in Easy Mode with the TutorialOverlay active
- [x] **Story**: As a first-time player, I want a funny little guide character (Chippy the Card Goblin) to appear on screen during the tutorial game and explain what's happening at each stage, so I understand how to play without the game feeling bloated or overwhelming. [KAN-78]
  * **Acceptance Criteria**:
    * **Given** a tutorial game is active
    * **When** the FSM transitions to a new game state (deal, peek, draw, resolve, jump-in, dutch, etc.)
    * **Then** Chippy's speech bubble updates with a contextual, concise tip (max 2 sentences)
    * **And** the player can press [NEXT >] to step through multi-part tips, or [SKIP TUTORIAL] to dismiss the overlay at any time
    * **And** one-off event tips appear when the player first drinks a beer, buys an ability, or Dutch is called

## Epic 17: Game Balance & Economy [KAN-79]
- [x] **Story**: As a player, I want powerful abilities like 'Perfect Match' and 'Polarity Shift' to be limited in supply (2 per match), so the game remains fair and strategic even when players have a lot of money. [KAN-80]
  * **Acceptance Criteria**:
    * **Given** a match is in progress
    * **When** 2 'Perfect Match' abilities have already been bought by any combination of players
    * **Then** the Chicken will no longer generate 'Perfect Match' for subsequent purchases
    * **And** the same rule applies independently to 'Polarity Shift'
    * **And** these limits reset every time a new match is initialized

