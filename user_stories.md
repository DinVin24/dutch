# Dutch - Agile User Stories

## Epic 1: Core Game Board & Arena
- [x] **Story**: As a player, I want to see a clear distinction between the deck, the discard pile, and all four player zones, so that I instantly understand the flow of cards.
  * **Acceptance Criteria**:
    * **Given** a new game is started
    * **When** the arena loads
    * **Then** the deck, discard pile, and 4 player zones are distinctly separated and visible.

- [x] **Story**: As a player, I want cards to be instantiated face down by default but easily flipped when the rules permit, so that the hidden-information mechanics of the game are preserved.
  * **Acceptance Criteria**:
    * **Given** cards are dealt to players
    * **When** a player receives their initial hand
    * **Then** all cards are face down and cannot be seen until an action explicitly flips them.

- [x] **Story**: As a player, I want the game board layout to respond gracefully to UI scaling and window resizing, so that the card positioning remains clean and legible.
  * **Acceptance Criteria**:
    * **Given** the game window is open
    * **When** the user resizes the window or changes resolution
    * **Then** the UI containers dynamically resize without overlapping or breaking the layout.

## Epic 2: Turn Cycle & Basic Moves
- [x] **Story**: As a player, I want to be required to draw a card from the deck at the start of my turn before doing anything else, so that the game enforces the primary rule.
  * **Acceptance Criteria**:
    * **Given** it is the beginning of a player's turn
    * **When** the player attempts to discard or swap without drawing
    * **Then** the action is blocked, and they are forced to draw first.

- [x] **Story**: As a player, I want to be able to drag the card I just drew directly to the discard pile if it's too high value (e.g. King), so that my turn ends immediately without penalty.
  * **Acceptance Criteria**:
    * **Given** the player just drew a card from the deck
    * **When** they drag it to the discard pile
    * **Then** the card is discarded, and their turn immediately ends.

- [x] **Story**: As a player, I want to be able to drag the card I just drew onto one of my face-down cards to swap them, dropping my old face-down card into the discard pile automatically, so that I can improve my score.
  * **Acceptance Criteria**:
    * **Given** the player has drawn a card
    * **When** they drop it onto one of their face-down cards
    * **Then** the drawn card takes its place, and the old face-down card is moved to the discard pile face-up.

## Epic 3: Special Card Mechanics
- [x] **Story**: As a player, when I discard a Queen, I want the UI to highlight all players' cards and allow me to click exactly one to secretly peek at it, so that I can gain information.
  * **Acceptance Criteria**:
    * **Given** a player discards a Queen
    * **When** the Queen effect triggers
    * **Then** the player can select one card on the board to secretly peek at, then their turn ends.

- [x] **Story**: As a player, when I discard a Jack, I want the game to prompt me to select two cards on the board to swap their places (without flipping them), so that I can strategize without breaking the hidden-information rule.
  * **Acceptance Criteria**:
    * **Given** a player discards a Jack
    * **When** the Jack effect triggers
    * **Then** two chosen cards blindly swap positions on the board without revealing their faces.

## Epic 4: The Jump-In System
- [ ] **Story**: As a player, I want the game to allow me to drag one of my cards to the discard pile at any point (even if it's not my turn) to attempt a Jump-In.
  * **Acceptance Criteria**:
    * **Given** another player's turn is active
    * **When** I click and drag a card to the discard pile
    * **Then** the game evaluates it as a Jump-In attempt.

- [ ] **Story**: As a player, if my Jump-In card matches the rank of the current top discard card, I want the game to accept the discard while maintaining the original turn order (it remains the turn of the player who was originally next), so that I am rewarded for my memory without disrupting the game flow.
  * **Acceptance Criteria**:
    * **Given** a card is dragged for a Jump-In
    * **When** its rank perfectly matches the discard pile's top card
    * **Then** the card is successfully discarded, and the current turn owner's turn resumes.

- [ ] **Story**: As a player, if my Jump-In card does not match the current top discard card, I want my card returned to its original position and the game to automatically deal me an extra penalty card, so that guessing is discouraged.
  * **Acceptance Criteria**:
    * **Given** a card is dragged for a Jump-In
    * **When** its rank does not match the top discard card
    * **Then** the card returns to the player's zone and the player receives an extra penalty card.

## Epic 5: End Game & Scoring
- [ ] **Story**: As a player, I want a "Call Dutch" button available during my turn that signals the final round, so that I can attempt to end the game when I believe I have the lowest score.
  * **Acceptance Criteria**:
    * **Given** it is the player's turn
    * **When** they click "Call Dutch"
    * **Then** a final round triggers for all other players before ending the game.

- [ ] **Story**: As a player, once my "Dutch" call cycles back to my turn, I want to be prompted to either confirm the call (ending the game) or cancel it (forfeiting my right to call Dutch again for the rest of the game), so that the game transitions into the Scoring Phase or safely continues.
  * **Acceptance Criteria**:
    * **Given** the round completes after a "Dutch" call
    * **When** it cycles back to the original caller
    * **Then** they must rigidly confirm or cancel the call.

- [ ] **Story**: As a player, when the game ends, I want all cards flipped face up and the points tallied according to the rules (Ace=1, Jack=11, Queen=12, King=13, King of Diamonds=0), so that the lowest scorer is immediately declared the winner.
  * **Acceptance Criteria**:
    * **Given** the game ends
    * **When** scoring initiates
    * **Then** all cards flip, point values are summed (excluding King of Diamonds which is 0), and a winner is declared.

## Epic 6: AI Opponents (Bots)
- [x] **Story**: As a system, I want the bot to have a simulated "memory" of cards it has peeked at, so that it can make rational decisions about which cards to swap or keep.
  * **Acceptance Criteria**:
    * **Given** a bot peeks at a card
    * **When** evaluating future actions
    * **Then** the bot correctly utilizes its stored memory of that card's rank.

- [x] **Story**: As a system, I want the bot to strategically evaluate the card it draws from the deck and appropriately discard unknown cards for low-value drawn cards, or discard high-value drawn cards, so that it attempts to win.
  * **Acceptance Criteria**:
    * **Given** a bot draws a card
    * **When** deciding whether to keep or discard
    * **Then** the bot mathematically weighs the drawn card against its known internal values.

- [x] **Story**: As a system, I want the bot to purposefully use its Queen and Jack abilities strategically (peeking at opponents or swapping worst/best cards) when available, rather than playing them randomly, so that it feels like a competitive player.
  * **Acceptance Criteria**:
    * **Given** a bot plays a Queen or Jack
    * **When** prompted for targets
    * **Then** the bot selects targets that maximize its positional advantage.

- [x] **Story**: As a system, I want the bot to recognize when an opponent discards a matching card, and automatically trigger a "Jump In" if the bot knows it possesses the match, so that it can utilize all valid game mechanics.
  * **Acceptance Criteria**:
    * **Given** an opponent discards a card
    * **When** the bot knows it holds a match
    * **Then** the bot initiates a Jump-In successfully.

## Epic 7: Visual Overhaul & Aesthetics
- [ ] **Story**: As a player, I want the game environment to feel dark and suspenseful with focused spotlights on the table and volumetric fog, so that the high-stakes atmosphere is reinforced.
  * **Acceptance Criteria**:
    * **Given** the game is played
    * **When** rendering the 3D scene
    * **Then** dynamic spotlights and fog create a tense atmosphere.

- [ ] **Story**: As a player, I want to see CRT scanlines, chromatic aberration, and digital glitch effects (Y2K aesthetic), so that the game feels like a piece of retro-tech.
  * **Acceptance Criteria**:
    * **Given** the camera renders the scene
    * **When** post-processing is applied
    * **Then** CRT, chromatic aberration, and glitch shaders are visible.

- [ ] **Story**: As a player, I want the UI to use high-saturation neons and glassmorphism contrasting with the dark 3D scene, so that interactive elements are striking and clear.
  * **Acceptance Criteria**:
    * **Given** a UI element is spawned
    * **When** it is displayed on screen
    * **Then** it features glassmorphic background blur and neon text.

- [ ] **Story**: As a player, I want every card move, swap, and draw to have "juice" (screen shake, card wobble, subtle particle trails), so that the gameplay feels physically satisfying.
  * **Acceptance Criteria**:
    * **Given** a card is manipulated
    * **When** it travels across the board
    * **Then** particles, screen shake, and smooth tweens enhance the impact.

## Epic 8: The Tavern Expansion (Beers, Money, and Abilities)
- [ ] **Story**: As a player, I want 5 physical 3D beers spawned at my side, representing lives, which I must drink from if I fail a Jump-In or instantly discard a drawn card, passing out when depleted.
  * **Acceptance Criteria**:
    * **Given** a player is active
    * **When** they fail a Jump-In or instantly discard
    * **Then** a 3D beer is consumed, and if 0 remain, the player passes out and is eliminated.

- [ ] **Story**: As a player, I want to earn money scaled to the rank of discarded cards (with Kings giving 0, King of Diamonds giving max, Aces giving high) to create an economic layer.
  * **Acceptance Criteria**:
    * **Given** a player successfully discards a card
    * **When** the discard resolves
    * **Then** the player is awarded currency scaled appropriately to the discard's value.

- [ ] **Story**: As a player, I want to click a hovering chicken to spend money and spawn an egg that cracks into a face-down Ability Card, which I can use anytime during my turn.
  * **Acceptance Criteria**:
    * **Given** a player has enough currency on their turn
    * **When** they click the chicken
    * **Then** money is deducted, an egg spawns and cracks, and a separate Ability component is added face-down to their play area.
