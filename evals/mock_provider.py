import json

def call_api(prompt, options, context):
    """
    Mock provider for Promptfoo evaluations.
    Inspects the input variables from promptfoo context and returns static,
    compliant responses to satisfy assertions during dry-run testing.
    """
    vars_dict = context.get('vars', {})
    
    # 1. Chippy Rules Assistant tests
    if 'question' in vars_dict:
        question = vars_dict['question'].lower()
        allowed_actions = vars_dict.get('allowed_actions', [])
        
        # Check specific question types
        if 'jump in' in question or 'jump-in' in question:
            return {
                'output': "Jump-In is a special move. If a card is discarded and you have a matching card in hand, you can play it immediately. Success reduces hand size; failure gives a penalty card and you drink a beer."
            }
        elif 'queen' in question:
            return {
                'output': "When you discard a Queen, you can secretly peek at any face-down card on the table (either yours or an opponent's)."
            }
        elif 'diamonds' in question or 'king of diamonds' in question:
            return {
                'output': "The King of Diamonds is a special card that counts as 0 points. You must hold it in your hand at the end of the game to count towards your score."
            }
        elif 'scoring' in question or 'score' in question:
            return {
                'output': "Scoring is calculated at the end of the game. Ace is 1, Jack is 11, Queen is 12, King of Diamonds is 0, and other Kings are 13. Lowest score wins."
            }
        elif 'chicken' in question:
            return {
                'output': "Click the chicken legs to spend money and receive an Ability Card. Buying an ability card spawns a face-down egg that cracks."
            }
        elif 'abilities' in question or 'ability' in question:
            return {
                'output': "There are special abilities like Bottoms Up, Refuel, Polarity Shift, Boulder, Uno Reverse, and Trim Off."
            }
        elif 'draw' in question:
            is_allowed = 'draw' in allowed_actions or 'draw_card' in allowed_actions
            if is_allowed:
                return {
                    'output': "Yes - you CAN draw a card right now."
                }
            else:
                return {
                    'output': "No - you can't draw a card right now."
                }
        elif 'end my turn' in question or 'end turn' in question:
            is_allowed = 'end_turn' in allowed_actions
            if is_allowed:
                return {
                    'output': "Yes - you CAN end your turn right now."
                }
            else:
                return {
                    'output': "No - you can't end your turn right now."
                }
        elif 'table' in question or 'scenery' in question or 'objects' in question:
            return {
                'output': "The tavern scenery (tables, chairs, cabinets, avatars) builds the run-down bar atmosphere."
            }
        elif 'call dutch' in question:
            # Check if call_dutch is allowed in the state vars
            is_allowed = False
            if isinstance(allowed_actions, list):
                is_allowed = 'call_dutch' in allowed_actions
            elif isinstance(allowed_actions, str):
                is_allowed = 'call_dutch' in allowed_actions
                
            if is_allowed:
                return {
                    'output': "Yes - you CAN call Dutch right now. If you call it, everyone else gets one last turn before scoring."
                }
            else:
                return {
                    'output': "No - you can't call Dutch right now. You can only call Dutch during the end choice phase of your turn."
                }
        
        return {
            'output': "This is a deterministic rules mock response for: " + vars_dict['question']
        }
        
    # 2. Dutch Player Agent bot tests
    if 'allowed_actions' in vars_dict:
        allowed = vars_dict['allowed_actions']
        
        # Ensure it is treated as a list for membership tests
        if not isinstance(allowed, list):
            allowed = [allowed]
            
        # Determine the action based on FSM rules
        if 'draw_card' in allowed or 'draw' in allowed:
            # Return expected tool call output format
            return {
                'output': json.dumps({
                    'name': 'draw_card',
                    'arguments': {}
                })
            }
        elif 'discard_drawn_card' in allowed:
            return {
                'output': json.dumps({
                    'name': 'discard_drawn_card',
                    'arguments': {}
                })
            }
        elif 'peek_ability' in allowed:
            return {
                'output': json.dumps({
                    'name': 'complete_queen_peek',
                    'arguments': {
                        'owner_player': 2,
                        'card_index': 0
                    }
                })
            }
        elif 'swap_ability' in allowed:
            return {
                'output': json.dumps({
                    'name': 'complete_jack_swap',
                    'arguments': {
                        'owner_player_a': 1,
                        'card_index_a': 0,
                        'owner_player_b': 2,
                        'card_index_b': 0
                    }
                })
            }
        elif 'confirm_dutch' in allowed:
            return {
                'output': json.dumps({
                    'name': 'confirm_dutch',
                    'arguments': {}
                })
            }
        elif 'buy_ability' in allowed:
            return {
                'output': json.dumps({
                    'name': 'buy_ability',
                    'arguments': {}
                })
            }
        elif 'use_ability' in allowed:
            return {
                'output': json.dumps({
                    'name': 'use_ability',
                    'arguments': {
                        'ability_name': 'Refuel'
                    }
                })
            }
        elif 'call_dutch' in allowed:
            return {
                'output': json.dumps({
                    'name': 'call_dutch',
                    'arguments': {}
                })
            }
            
        return {
            'output': json.dumps({
                'name': 'end_turn',
                'arguments': {}
            })
        }
        
    return {
        'output': 'Mock response'
    }
