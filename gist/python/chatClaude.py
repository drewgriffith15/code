import os
from anthropic import AnthropicFoundry 
from dotenv import load_dotenv
from pathlib import Path


env_path = os.getenv('DOTENV')
# env_path = r"C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\.env"
if env_path and Path(env_path).exists():
    load_dotenv(env_path, override=True)

CLAUDE_API_KEY   = os.getenv('CLAUDE_API_KEY')
CLAUDE_ENDPOINT = os.getenv('CLAUDE_ENDPOINT') 

_cumulative_cost = 0

MODEL_PRICING = {
    # Anthropic
    'claude-haiku-4-5':    (1.00,   5.00),
    'claude-sonnet-4-6':   (3.00,  15.00),
    'claude-opus-4-6':     (5.00,  25.00),
}
DEFAULT_PRICING = (99.0, 99.0, 99.0)


def chat_claude(system_prompt, messages, model='claude-sonnet-4-6', max_tokens=16384, thinking_budget=1024):
    
    global _cumulative_cost

    client = AnthropicFoundry(api_key=CLAUDE_API_KEY, base_url=CLAUDE_ENDPOINT)

    message = client.messages.create(
        model=model,
        system=system_prompt,
        messages=messages,
        max_tokens=max(max_tokens, thinking_budget + max_tokens),
        timeout=600.0,
        cache_control={"type": "ephemeral"}, # eph does the 5m caching at end of every chat
        thinking={"type": "enabled", "budget_tokens": thinking_budget},
    )

    u = message.usage
    it = u.input_tokens
    ot = u.output_tokens
    ct = getattr(u, 'cache_read_input_tokens', 0) or 0
    cw = getattr(u, 'cache_creation_input_tokens', 0) or 0

    i_rate, o_rate = MODEL_PRICING.get(model, DEFAULT_PRICING)
    tks = 1_000_000
    cost = ((it * i_rate / tks) + (ct * i_rate * 0.1 / tks) + (cw * i_rate * 1.25 / tks) + (ot * o_rate / tks) )

    _cumulative_cost += cost
    cumulative = _cumulative_cost
    
    tokens_info = { 'input_tokens': it, 'cached_tokens': ct, 'cache_creation_tokens': cw, 'output_tokens': ot, 'spend_amt': f"${cost:.6f}", 'cumulative_cost': f"${cumulative:.4f}",}
    
    print(f"[{model}] ${cost:.6f} | Cumulative: ${cumulative:.4f} | In:{it} Cache(R:{ct} W:{cw}) | Out:{ot}")

    text = "".join(b.text for b in message.content if b.type == 'text')
    return text, message.id, tokens_info
    
if __name__ == "__main__":
    
    system_prompt = "You are a helpful assistant."
    messages = [{"role": "user", "content": "What is 1+1"}]
    text, response_id, tokens_info = chat_claude(system_prompt, messages)
    
    print(text)
    print(tokens_info)