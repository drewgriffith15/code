import os
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
    "high":   8000,
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
    # No adaptive models remain; always resolve to 'enabled' unless auto
    if thinking_type == 'auto':
        return 'enabled'
    return thinking_type


def _build_thinking_param(resolved_type: str, budget_tokens: int) -> dict:
    if resolved_type == 'disabled':
        return {"type": "disabled"}
    return {"type": resolved_type, "budget_tokens": budget_tokens}


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
    model:            str           = 'claude-haiku-4-5',
    max_tokens:       int           = 4096,
    thinking_budget:  int           = 1024,
    thinking_type:    str           = 'auto',
    reasoning_effort: Optional[str] = None,
) -> Tuple[str, str, dict]:
    """Calls AnthropicFoundry. Returns (text, message_id, tokens_info)."""
    global _cumulative_cost

    if model in _NO_THINKING_MODELS:
        thinking_type    = 'disabled'
        reasoning_effort = None

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
        "timeout":    300.0,
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
        (it * i_rate          / tks) +
        (ct * i_rate * 0.1    / tks) +
        (cw * i_rate * 1.25   / tks) +
        (ot * o_rate          / tks)
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

    effort_label = reasoning_effort if reasoning_effort else f"budget={effective_budget}"
    print(
        f"[{model}] thinking={resolved_type} effort={effort_label} | "
        f"${cost:.6f} | Cumulative: ${cumulative:.4f} | "
        f"In:{it} Cache(R:{ct} W:{cw}) | Out:{ot}"
    )

    text = "".join(b.text for b in message.content if b.type == 'text')
    return text, message.id, tokens_info


# ----------------------------- File Utilities -----------------------------
def get_file_content(file_path: str) -> str:
    """Read file content with encoding fallback."""
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
    """Return descriptive label for file extension."""
    ext = Path(file_path).suffix.lower().lstrip(".")
    mapping = {"py": "Python", "sql": "SQL", "ipynb": "Jupyter"}
    return mapping.get(ext, f"{ext} file")


def write_content_to_file(file_path: str, content: str) -> None:
    """Writes content to disk."""
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)


def strip_existing_header(source: str, file_ext: str) -> str:
    """
    Removes any existing comment-only header block from the top of the source.

    Scans lines from the top and discards every line that is either blank or
    composed entirely of comment tokens (# for Python, -- for SQL/everything
    else). Scanning stops at the first line that contains real code, which is
    preserved along with everything that follows it.
    """
    ext   = file_ext.lower().lstrip(".")
    token = "#" if ext == "py" else "--"
    lines = source.splitlines()

    first_code_index = 0
    for i, line in enumerate(lines):
        stripped = line.strip()
        # A line is part of the header if it is blank or is a pure comment
        if stripped == "" or stripped.startswith(token):
            first_code_index = i + 1
        else:
            # First non-comment, non-blank line found — stop here
            first_code_index = i
            break
    else:
        # Every line was a comment or blank; return empty string so the
        # pipeline still functions without raising on an all-header file.
        return ""

    # Rejoin from the first real code line, stripping any leading blank lines
    # that sat between the header block and the actual code.
    remaining = "\n".join(lines[first_code_index:]).lstrip("\n")
    return remaining


def extract_header_block(md: str) -> str:
    """
    Extracts the header comment block from the model response.

    Attempts to pull the last fenced code block first; if none is found,
    falls back to the raw response text. The result contains only the
    comment lines that will be prepended to the original source file.
    """
    pattern = re.compile(r"```([a-zA-Z0-9_+\-]*)\n(.*?)\n```", re.DOTALL)
    blocks  = pattern.findall(md or "")
    if blocks:
        return blocks[-1][1].strip()
    return md.strip()


def ensure_header_commented(header_text: str, target_ext: str) -> str:
    """
    Guarantees every line in the header block is a valid comment
    for the target language. Prose lines not already prefixed are
    wrapped with the appropriate token.
    """
    ext   = target_ext.lower().lstrip(".")
    token = "#" if ext == "py" else "--"
    lines = header_text.splitlines()
    out   = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            out.append("")
        elif stripped.startswith(token):
            out.append(line)
        else:
            out.append(f"{token} {line}")
    return "\n".join(out)


# ----------------------------- Orchestration -----------------------------
def header_only_generate(
    script_path: str,
    prompt_path: str,
    model:       str = "claude-haiku-4-5",
) -> str:
    """
    Single-step pipeline:
      1. Read the existing source file.
      2. Strip any existing comment header from the top so the model never
         sees a stale header and a double-header is never written to disk.
      3. Call the model with the header-generation system prompt against
         the clean (header-free) source code.
      4. Extract and sanitize only the returned header block.
      5. Prepend the new header to the clean source with a single separator.
      6. Overwrite the input file in-place — no new file is created.
    """
    print(f"[HeaderOnly] Starting single-step header generation with {model}...")

    target_ext    = Path(script_path).suffix.lstrip(".")
    raw_code      = get_file_content(script_path)
    system_prompt = get_file_content(prompt_path)
    file_type     = get_file_type(script_path)

    print(f"[HeaderOnly] Source file read. Length: {len(raw_code)} chars.")
    print(f"[HeaderOnly] Detected file type: {file_type}")

    # Strip any pre-existing header so the model receives only real code
    # and so the final write never appends a new header onto an old one.
    clean_code = strip_existing_header(raw_code, target_ext)
    stripped_chars = len(raw_code) - len(clean_code)
    print(f"[HeaderOnly] Stripped {stripped_chars} chars of existing header block.")

    if not clean_code.strip():
        raise RuntimeError("[HeaderOnly] Source file contains no code after header removal.")

    user_message = (
        f"FILE TYPE: {file_type}\n\n"
        f"SOURCE CODE:\n{clean_code}\n\n"
        "INSTRUCTION: Analyze the source code above and generate ONLY the "
        "Standardized Documentation Header for it. Do NOT rewrite, modify, "
        "or repeat any of the source code. Output the header block only, "
        "inside a single fenced code block matching the file type."
    )

    raw_response, _, tokens_info = chat_claude(
        system_prompt=system_prompt,
        messages=[{"role": "user", "content": user_message}],
        model=model,
        max_tokens=2048,
    )

    if not raw_response:
        raise RuntimeError("[HeaderOnly] Model returned an empty response.")

    header_block = extract_header_block(raw_response)
    header_block = ensure_header_commented(header_block, target_ext)

    if not header_block:
        raise RuntimeError("[HeaderOnly] Could not extract a valid header from model response.")

    # Compose: header → single separator → one blank line → clean code
    final_content = f"{header_block}\n\n{clean_code}"

    write_content_to_file(script_path, final_content)
    print(f"\n[HeaderOnly] Header prepended. Input file updated in-place:\n{script_path}")
    print(f"[HeaderOnly] Total cost this run: {tokens_info['cumulative_cost']}")

    return final_content


# ----------------------------- Entry Point -----------------------------
if __name__ == "__main__":
    try:
        prompt_path = (
            r"C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\BitBucket\tank\gist\prompt\create_slopdoc_header.md"
            
        )

        script_path = (
            r"C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\MillenniumFalcon\etl_aa_secfhtcoll_refresh_20260414.sql"
        )

        header_only_generate(
            script_path=script_path,
            prompt_path=prompt_path,
            model="claude-haiku-4-5",
        )
    except Exception as e:
        print(f"Pipeline Error: {e}")
