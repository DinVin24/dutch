# Dutch - Agile User Stories

## Epic 1: Core Game Board & Arena
- **Story**: As a player, I want to see a clear distinction between the deck, the discard pile, and all four player zones, so that I instantly understand the flow of cards.
- **Story**: As a player, I want cards to be instantiated face down by default but easily flipped when the rules permit, so that the hidden-information mechanics of the game are preserved.
- **Story**: As a player, I want the game board layout to respond gracefully to UI scaling and window resizing, so that the card positioning remains clean and legible.

## Epic 2: Turn Cycle & Basic Moves
- **Story**: As a player, I want to be required to draw a card from the deck at the start of my turn before doing anything else, so that the game enforces the primary rule.
- **Story**: As a player, I want to be able to drag the card I just drew directly to the discard pile if it's too high value (e.g. King), so that my turn ends immediately without penalty.
- **Story**: As a player, I want to be able to drag the card I just drew onto one of my face-down cards to swap them, dropping my old face-down card into the discard pile automatically, so that I can improve my score.

## Epic 3: Special Card Mechanics
- **Story**: As a player, when I discard a Queen, I want the UI to highlight all players' cards and allow me to click exactly one to secretly peek at it, so that I can gain information.
- **Story**: As a player, when I discard a Jack, I want the game to prompt me to select two cards on the board to swap their places (without flipping them), so that I can strategize without breaking the hidden-information rule.

## Epic 4: The Jump-In System
- **Story**: As a player, I want the game to allow me to drag one of my cards to the discard pile at any point (even if it's not my turn) to attempt a Jump-In.
- **Story**: As a player, if my Jump-In card matches the rank of the current top discard card, I want the game to accept the discard and shift the turn order to the player immediately after me, so that I am rewarded for my memory.
- **Story**: As a player, if my Jump-In card *does not* match the current top discard card, I want my card returned to its original position and the game to automatically deal me an extra penalty card, so that guessing is discouraged.

## Epic 5: End Game & Scoring
- **Story**: As a player, I want a "Call Dutch" button available during my turn that signals the final round, so that I can attempt to end the game when I believe I have the lowest score.
- **Story**: As a player, once my "Dutch" call cycles back to my turn, I want to be able to officially end the game or cancel it, so that the game transitions into the Scoring Phase.
- **Story**: As a player, when the game ends, I want all cards flipped face up and the points tallied according to the rules (Ace=1, Jack=11, Queen=12, King=13, King of Diamonds=0), so that the lowest scorer is immediately declared the winner.

## Epic 6: AI Opponents (Bots)
- **Story**: As a system, I want the bot to have a simulated "memory" of cards it has peeked at, so that it can make rational decisions about which cards to swap or keep.
- **Story**: As a system, I want the bot to evaluate the top discarded card against its known high-value cards, so that it attempts to Jump-In when advantageous.
- **Story**: As a player, I want the bots' turns to take 1-2 seconds with clear visual cues summarizing their actions (e.g., "Bot 2 swapped a card"), so that the pacing feels natural and I can follow the state of the game.
- **Story**: As a system, I want the bot to track the number of cards its opponents have and their visible score potential, so that it can strategically decide when to call "Dutch".
