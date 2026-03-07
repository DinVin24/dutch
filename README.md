# Dutch

## Setup
- Each player is dealt 4 cards face down.
- Players may look at any 2 of their cards at the start of the game.
- Cards remain face down for the rest of the game.

## Turns
- Draw a card from the deck and look at it.
- Decide if you either:
  - Discard it onto the pile.
  - Swap it with one of your face-down cards.

## Special Moves
- Jump-in:
  If a player knows they have a card that matches the last one that was discarded, they can discard it, even if it isn't their turn.
  - If the card is a match, you get to discard it.
  - If the card isn't a match, you keep it and also draw a new card without looking at it.
- Special cards:
  - Queen -> Look at any face-down card on the table (yours or an opponent's)
  - Jack -> Swap any two cards on the table

## Scoring
- The goal of the game is to have the lowest score.
- Points per card:
  - Ace = 1, Two = 2, ..., Jack = 11, Queen = 12, King = 13
  - King of Diamonds = 0.

## Calling Dutch
- On your turn, you may call "Dutch" if you believe you have the lowest score on the table.
- When you call Dutch, everybody gets notified, and the game progresses one more full turn for everyone.
- When it is your turn again, you have two choices:
  - **Confirm**: End the game immediately. All cards are flipped face-up and the player with the lowest score wins.
  - **Cancel**: Continue the game. However, if you cancel, you cannot call Dutch again for the remainder of the game.

## Winning
- When the game ends, all player reveal their cards.
- The player with the lowest score wins.
- In case of a tie, the player with fewer cards wins.
- If you discard all of your cards before the game ends, you win.

## Developer Setup
- Run `git config core.hooksPath .githooks` after cloning to enable the project git hooks.
