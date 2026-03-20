# Dutch - Agile User Stories

## Epic 1: Core Game Board & Arena
- [x] **Story**: As a player, I want to see a clear distinction between the deck, the discard pile, and all four player zones, so that I instantly understand the flow of cards.
- [x] **Story**: As a player, I want cards to be instantiated face down by default but easily flipped when the rules permit, so that the hidden-information mechanics of the game are preserved.
- [x] **Story**: As a player, I want the game board layout to respond gracefully to UI scaling and window resizing, so that the card positioning remains clean and legible.

## Epic 2: Turn Cycle & Basic Moves
- [x] **Story**: As a player, I want to be required to draw a card from the deck at the start of my turn before doing anything else, so that the game enforces the primary rule.
- [x] **Story**: As a player, I want to be able to drag the card I just drew directly to the discard pile if it's too high value (e.g. King), so that my turn ends immediately without penalty.
- [x] **Story**: As a player, I want to be able to drag the card I just drew onto one of my face-down cards to swap them, dropping my old face-down card into the discard pile automatically, so that I can improve my score.

## Epic 3: Special Card Mechanics
- [x] **Story**: As a player, when I discard a Queen, I want the UI to highlight all players' cards and allow me to click exactly one to secretly peek at it, so that I can gain information.
- [x] **Story**: As a player, when I discard a Jack, I want the game to prompt me to select two cards on the board to swap their places (without flipping them), so that I can strategize without breaking the hidden-information rule.

## Epic 4: The Jump-In System
- [ ] **Story**: As a player, I want the game to allow me to drag one of my cards to the discard pile at any point (even if it's not my turn) to attempt a Jump-In.
- [ ] **Story**: As a player, if my Jump-In card matches the rank of the current top discard card, I want the game to accept the discard while maintaining the original turn order (it remains the turn of the player who was originally next), so that I am rewarded for my memory without disrupting the game flow.
- [ ] **Story**: As a player, if my Jump-In card *does not* match the current top discard card, I want my card returned to its original position and the game to automatically deal me an extra penalty card, so that guessing is discouraged.

## Epic 5: End Game & Scoring
- [ ] **Story**: As a player, I want a "Call Dutch" button available during my turn that signals the final round, so that I can attempt to end the game when I believe I have the lowest score.
- [ ] **Story**: As a player, once my "Dutch" call cycles back to my turn, I want to be prompted to either confirm the call (ending the game) or cancel it (forfeiting my right to call Dutch again for the rest of the game), so that the game transitions into the Scoring Phase or safely continues.
- [ ] **Story**: As a player, when the game ends, I want all cards flipped face up and the points tallied according to the rules (Ace=1, Jack=11, Queen=12, King=13, King of Diamonds=0), so that the lowest scorer is immediately declared the winner.

## Epic 6: AI Opponents (Bots)
- [x] **Story**: As a system, I want the bot to have a simulated "memory" of cards it has peeked at, so that it can make rational decisions about which cards to swap or keep.
- [x] **Story**: As a system, I want the bot to strategically evaluate the card it draws from the deck and appropriately discard unknown cards for low-value drawn cards, or discard high-value drawn cards, so that it attempts to win.
- [x] **Story**: As a system, I want the bot to purposefully use its Queen and Jack abilities strategically (peeking at opponents or swapping worst/best cards) when available, rather than playing them randomly, so that it feels like a competitive player.
- [x] **Story**: As a system, I want the bot to recognize when an opponent discards a matching card, and automatically trigger a "Jump In" if the bot knows it possesses the match, so that it can utilize all valid game mechanics.
## Epic 7: Visual Overhaul & Juicy Aesthetics (Y2K/Analog Horror)
- [ ] **Story**: As a player, I want the game environment to feel dark and suspenseful (like Resident Evil 7 / Buckshot Roulette), with focused spotlights on the table and volumetric fog, so that the high-stakes atmosphere is reinforced.
- [ ] **Story**: As a player, I want to see CRT scanlines, chromatic aberration, and digital glitch effects (Y2K aesthetic), so that the game feels like a piece of retro-tech or a lost digital artifact.
- [ ] **Story**: As a player, I want the UI to use high-saturation neons and glassmorphism (Balatro style), contrasting with the dark 3D scene, so that interactive elements are striking and clear.
- [ ] **Story**: As a player, I want every card move, swap, and draw to have "juice" (screen shake, card wobble, subtle particle trails), so that the gameplay feels physically satisfying.

## Epic 8: The Tavern Mechanics (Beers, Money, Chicken & Abilities)
- [ ] **Story**: As a player, I want to see 5 3D rendered beers on my side of the table that act as my "lives," so that I know how close I am to elimination.
- [ ] **Story**: As a player, when I instantly discard a card I just drew or fail a Jump-In, I want to automatically "drink" one beer as a penalty.
- [ ] **Story**: As a player, when I consume my 5th beer, I want to pass out and be eliminated from the game, so that survival becomes a core mechanic.
- [ ] **Story**: As a player, when I discard a card, I want to earn in-game money scaled to the card's value (King of Diamonds = Most, Aces = High, Spades/Hearts/Clubs Kings = 0), so that I have a currency to spend.
- [ ] **Story**: As a player, I want to see a hovering chicken at the top of the table that I can click on to spend my money, so that I have a shop mechanic.
- [ ] **Story**: As a player, when I buy from the chicken, I want it to lay an egg that lands on my side, cracks, and reveals an ability card/token that is then turned face-down, so that my abilities remain a secret.
- [ ] **Story**: As a player, I want playing an ability to be a "free action" during my turn that doesn't conflict with my main draw/discard/swap action, so that I can strategize freely.
- [ ] **Story**: As a player, I want to be able to use a variety of offensive abilities (e.g., force drink, give highest deck card, skip turn, Jumpscare, shuffle opponent's cards) to disrupt my opponents.
- [ ] **Story**: As a player, I want to be able to use a variety of defensive/utility abilities (e.g., extra beer, remove highest card, double/halve card values for scoring, reverse turn order, Chaotic Reset) to improve my own standing.
