import os
import datetime
import re
import json
from anthropic import AnthropicFoundry
from dotenv import load_dotenv
from pathlib import Path
from typing import Optional, Tuple

env_path = os.getenv('DOTENV')
if env_path and Path(env_path).exists():
    load_dotenv(env_path, override=True)

CLAUDE_API_KEY  = os.getenv('CLAUDE_API_KEY')
CLAUDE_ENDPOINT = os.getenv('CLAUDE_ENDPOINT')

_cumulative_cost = 0.0

MODEL_PRICING = {
    'claude-haiku-4-5':  (1.00,   5.00),
    'claude-sonnet-4-6': (3.00,  15.00),
}
DEFAULT_PRICING = (99.0, 99.0)

_NO_THINKING_MODELS = frozenset({
    'claude-haiku-4-5',
})

ALLOWED_REASONING_EFFORT = {"low", "medium", "high"}

_EFFORT_BUDGET_MAP: dict[str, int] = {
    "low":    1024,
    "medium": 4000,
    "high":  8000,
}


def _resolve_thinking_budget(
    reasoning_effort: Optional[str],
    explicit_budget:  int,
) -> int:
    if reasoning_effort is None:
        return explicit_budget
    effort = reasoning_effort.lower()
    if effort not in ALLOWED_REASONING_EFFORT:
        raise ValueError(
            f"Invalid reasoning_effort '{reasoning_effort}'. "
            f"Allowed values: {sorted(ALLOWED_REASONING_EFFORT)}"
        )
    return _EFFORT_BUDGET_MAP[effort]


def _resolve_thinking_type(model: str, thinking_type: str) -> str:
    if thinking_type == 'auto':
        return 'disabled' if model in _NO_THINKING_MODELS else 'enabled'
    return thinking_type


def _build_thinking_param(resolved_type: str, budget_tokens: int) -> dict:
    if resolved_type == 'disabled':
        return {"type": "disabled"}
    return {"type": "enabled", "budget_tokens": budget_tokens}


def _compute_max_tokens(
    max_tokens:      int,
    thinking_budget: int,
    resolved_type:   str,
) -> int:
    if resolved_type == 'disabled':
        return max_tokens
    return thinking_budget + max_tokens


# ----------------------------- Core API Call -----------------------------
def chat_claude(
    system_prompt:    str,
    messages:         list,
    model:            str           = 'claude-sonnet-4-6',
    max_tokens:       int           = 16000,
    thinking_budget:  int           = 4000,
    thinking_type:    str           = 'auto',
    reasoning_effort: Optional[str] = None,
) -> Tuple[str, str, dict]:
    global _cumulative_cost

    if model in _NO_THINKING_MODELS:
        thinking_type    = 'disabled'
        reasoning_effort = None

    if reasoning_effort is not None:
        effort = reasoning_effort.lower()
        if effort not in ALLOWED_REASONING_EFFORT:
            raise ValueError(
                f"Invalid reasoning_effort '{reasoning_effort}'. "
                f"Allowed values: {sorted(ALLOWED_REASONING_EFFORT)}"
            )
        reasoning_effort = effort

    effective_budget = _resolve_thinking_budget(reasoning_effort, thinking_budget)
    resolved_type    = _resolve_thinking_type(model, thinking_type)
    thinking_param   = _build_thinking_param(resolved_type, effective_budget)
    effective_max    = _compute_max_tokens(max_tokens, effective_budget, resolved_type)

    client = AnthropicFoundry(api_key=CLAUDE_API_KEY, base_url=CLAUDE_ENDPOINT)

    request_kwargs = {
        "model":      model,
        "system":     system_prompt,
        "messages":   messages,
        "max_tokens": effective_max,
        "timeout":    600.0,
        "thinking":   thinking_param,
    }

    try:
        message = client.messages.create(
            **request_kwargs,
            cache_control={"type": "ephemeral"},
        )
    except TypeError:
        message = client.messages.create(**request_kwargs)

    u  = message.usage
    it = u.input_tokens
    ot = u.output_tokens
    ct = getattr(u, 'cache_read_input_tokens',     0) or 0
    cw = getattr(u, 'cache_creation_input_tokens', 0) or 0

    i_rate, o_rate = MODEL_PRICING.get(model, DEFAULT_PRICING)
    tks  = 1_000_000
    cost = (
        (it * i_rate        / tks) +
        (ct * i_rate * 0.1  / tks) +
        (cw * i_rate * 1.25 / tks) +
        (ot * o_rate        / tks)
    )

    _cumulative_cost += cost
    cumulative = _cumulative_cost

    tokens_info = {
        'input_tokens':          it,
        'cached_tokens':         ct,
        'cache_creation_tokens': cw,
        'output_tokens':         ot,
        'thinking_type':         resolved_type,
        'reasoning_effort':      reasoning_effort or 'explicit_budget',
        'effective_budget':      effective_budget,
        'spend_amt':             f"${cost:.6f}",
        'cumulative_cost':       f"${cumulative:.4f}",
    }

    effort_label = (
        ""
        if resolved_type == "disabled"
        else (reasoning_effort if reasoning_effort else f"budget={effective_budget}")
    )

    effort_str = f" effort={effort_label}" if effort_label else ""
    print(
        f"     {model}: thinking={resolved_type}{effort_str} | "
        f"~${cost:.6f} | Cumulative: ~${cumulative:.4f} | "
        f"In:{it} Cache(R:{ct} W:{cw}) | Out:{ot}"
    )

    text = "".join(b.text for b in message.content if b.type == 'text')
    return text, message.id, tokens_info


# ----------------------------- File Utilities -----------------------------
def get_file_content(file_path: str) -> str:
    ext = Path(file_path).suffix.lower().lstrip(".")
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            if ext == "ipynb":
                nb = json.load(f)
                return "\n".join(
                    ["\n".join(c.get("source", []))
                     for c in nb["cells"] if c.get("cell_type") == "code"]
                )
            return f.read()
    except UnicodeDecodeError:
        with open(file_path, "r", encoding="latin-1") as f:
            return f.read()


def get_file_type(file_path: str) -> str:
    ext = Path(file_path).suffix.lower().lstrip(".")
    mapping = {"py": "Python", "sql": "SQL", "ipynb": "Jupyter"}
    return mapping.get(ext, f"{ext} file")


def generate_export_path(script_path: str) -> str:
    directory, file_name = os.path.split(script_path)
    name, ext = os.path.splitext(file_name)
    ts   = datetime.datetime.now().strftime("%Y%m%d%H%M")
    name = re.sub(r"_(\d{12})$|_(\d{8})$", "", name)
    return os.path.join(directory, f"{name}_{ts}{ext}")


def write_content_to_file(file_path: str, content: str) -> None:
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)


# ----------------------------- Markdown & Sanitization -----------------------------
def extract_last_code_block(md: str) -> Tuple[Optional[str], Optional[str]]:
    pattern = re.compile(r"```([a-zA-Z0-9_+\-]*)\n(.*?)\n```", re.DOTALL)
    blocks  = pattern.findall(md or "")
    if not blocks:
        return None, None
    return blocks[-1][1], blocks[-1][0].strip().lower()


# ----------------------------- Orchestration -----------------------------
def generate(
    script_path:      str,
    prompt_path:      str,
    model:            str           = "claude-sonnet-4-6",
    thinking_type:    str           = "auto",
    reasoning_effort: Optional[str] = None,
) -> str:
    if reasoning_effort is not None:
        effort = reasoning_effort.lower()
        if effort not in ALLOWED_REASONING_EFFORT:
            raise ValueError(
                f"Invalid reasoning_effort '{reasoning_effort}'. "
                f"Allowed values: {sorted(ALLOWED_REASONING_EFFORT)}"
            )
        reasoning_effort = effort

    print(f"- BEGIN: Starting code generation... (reasoning_effort={reasoning_effort or 'explicit_budget'})")

    export_file_path = generate_export_path(script_path)

    script_text   = get_file_content(script_path)
    system_prompt = get_file_content(prompt_path)

    print(f"- GENERATING: Running {model}...")

    output_text, _, _ = chat_claude(
        system_prompt,
        [{"role": "user", "content": script_text}],
        model=model,
        thinking_type=thinking_type,
        reasoning_effort=reasoning_effort,
    )

    if not output_text:
        raise RuntimeError("Generation failed: empty response from model.")

    final_code, _ = extract_last_code_block(output_text)
    final_code    = final_code or output_text

    write_content_to_file(export_file_path, final_code.strip())
    print(f"✓ END: Script successfully generated at:\n{export_file_path}")

    return final_code.strip()

# ----------------------------- Entry Point -----------------------------
if __name__ == "__main__":
    try:
        prompt_path = (
            r"C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\BitBucket\tank\gist\prompt\create_code.md"
        )

        script_path = (
            r"c:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\MillenniumFalcon\create or replace package load_aa_etl_golem.sql"
        )

        generate(
            script_path=script_path,
            prompt_path=prompt_path,
            thinking_type="auto",
            reasoning_effort="high",
        )
    except Exception as e:
        print(f"Pipeline Error: {e}")
