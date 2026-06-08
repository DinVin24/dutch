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
