# Dutch

Dutch is a rules-heavy card game of memory, strategy, and high-stakes social interaction. The goal is to finish with the lowest score, but with abilities, money, and "beers" at play, the path to victory is rarely straight.

## 🎴 The Basics
- **Setup**: Each player is dealt 4 cards face down. You may peek at any 2 at the start.
- **Turns**: Draw a card, decide to either **Discard** it or **Swap** it with one of your face-down cards.
- **Winning**: The player with the lowest score when the game ends wins. If you discard all your cards, you win immediately.

## 🍻 Penalty System (Beers)
Each player starts with **5 Beers**. Certain mistakes force you to "drink":
- **Failed Jump-In**: Trying to jump in with a card that doesn't match.
- **Instant Discard**: Drawing a card and immediately discarding it without swapping or using its ability (if applicable).
- **Passing Out**: Once you drink all 5 beers, you are eliminated from the round.

## 💰 Economy & Abilities
- **Money**: Discarding cards earns you money based on the card's value. 
    - **Aces & King of Diamonds**: High value.
    - **Other Kings**: Zero value.
- **The Chicken**: A 3D chicken hovers over the table. Click its legs to spend money and receive an **Ability Card**.
- **Ability Cards**: These are kept face-down and can be used on your turn. They do not count toward your hand score.

### Standard Card Abilities (Discarded)
- **Queen**: Look at any face-down card on the table.
- **Jack**: Swap any two cards on the table.
- **King of Diamonds**: 0 points (lowest possible).

### Special Ability Tokens
- **Force Drink**: Make another player drink a beer.
- **Extra Beer**: Recover one of your beer slots.
- **Purge**: Remove the highest card from your hand.
- **Sabotage**: Give an opponent the highest card from the deck.
- **Uno Reverse**: Reverse the turn order.
- **Block**: Skip an opponent's turn.
- **Doubler/Halver**: Manipulate the scoring value of a player's hand.

## ⚡ Special Moves
- **Jump-In**: If you have a card matching the last one discarded, you can play it even if it's not your turn. 
    - **Success**: Your hand size decreases.
    - **Failure**: You draw a penalty card and drink a beer.
- **Calling Dutch**: If you think you have the lowest score, call "Dutch". Everyone gets one last turn. You then **Confirm** to end or **Cancel** (forfeiting your right to call again).

## 🛠️ Developer Setup
- Run `git config core.hooksPath .githooks` after cloning.
- See `DESIGN.md` for technical architecture and FSM details.
