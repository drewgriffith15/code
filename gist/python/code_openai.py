import os
import re
import json
import datetime
from pathlib import Path
from typing import List, Dict, Optional, Tuple
import openai

# ----------------------------- Metrics / Costs -----------------------------
input_tokens: int = 0
output_tokens: int = 0
total_spend: float = 0.0

ALLOWED_REASONING_EFFORT = {"low", "medium", "high"}

def _validate_reasoning_effort(reasoning_effort: Optional[str]) -> Optional[str]:
    """Normalize and validate reasoning effort for GPT-5 family models."""
    if reasoning_effort is None:
        return None
    effort = reasoning_effort.strip().lower()
    if effort not in ALLOWED_REASONING_EFFORT:
        raise ValueError(
            f"Invalid reasoning_effort '{reasoning_effort}'. "
            f"Allowed values: {sorted(ALLOWED_REASONING_EFFORT)}"
        )
    return effort


def _extract_output_text_from_responses(resp: object) -> Optional[str]:
    """Robustly extract text from Azure Responses API payloads."""
    txt = getattr(resp, "output_text", None)
    if isinstance(txt, str) and txt.strip():
        return txt

    try:
        output = getattr(resp, "output", None)
        if isinstance(output, list):
            parts: List[str] = []
            for item in output:
                content = getattr(item, "content", None)
                if isinstance(content, list):
                    for seg in content:
                        seg_text = getattr(seg, "text", None)
                        if isinstance(seg_text, str) and seg_text.strip():
                            parts.append(seg_text)
            if parts:
                return "\n".join(parts)
    except Exception:
        pass

    try:
        return resp.output[1].content[0].text  # type: ignore[attr-defined]
    except Exception:
        return None


def callgpt(
    messages: List[Dict[str, str]],
    model: str = "gpt-5-mini",
    reasoning_effort: Optional[str] = None,
    previous_response_id: Optional[str] = None,
) -> Optional[str]:
    """Azure OpenAI caller supporting chat.completions and responses API."""
    global input_tokens, output_tokens, total_spend

    endpoint_key = "AZURE_END_POINT"
    api_key_name = "AZURE_OPENAI_KEY"

    try:
        if model == "gpt-4.1":
            client = openai.AzureOpenAI(
                azure_endpoint=os.getenv(endpoint_key),
                api_key=os.getenv(api_key_name),
                api_version="2025-01-01-preview",
            )
            completion = client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=0,
                max_tokens=16000,
                top_p=1,
                frequency_penalty=0.0,
                presence_penalty=0.0,
                stop=None,
            )
            usage = completion.usage
            input_tokens = usage.input_tokens
            output_tokens = usage.output_tokens
            return completion.choices[0].message.content

        elif model in ["gpt-5-mini", "gpt-5"]:
            client = openai.AzureOpenAI(
                azure_endpoint=os.getenv(endpoint_key),
                api_key=os.getenv(api_key_name),
                api_version="2025-04-01-preview",
            )
            effort = _validate_reasoning_effort(reasoning_effort)
            completion = client.responses.create(
                model=model,
                input=messages, 
                max_output_tokens=120000,
                reasoning={"effort": effort} if effort else None,
                text={"verbosity": "medium"},
                previous_response_id=previous_response_id,
            )

            usage = completion.usage
            cached_tokens = getattr(usage.input_tokens_details, "cached_tokens", 0)
            input_tokens = usage.input_tokens
            output_tokens = usage.output_tokens

            tks = 1_000_000
            if model == "gpt-5-mini":
                cached_cost, input_cost, output_cost = 0.025/tks, 0.25/tks, 2.00/tks
            else:  # gpt-5 / gpt-4.1 fallback
                cached_cost, input_cost, output_cost = 0.125/tks, 1.25/tks, 10.00/tks

            non_cached = input_tokens - cached_tokens
            cost = (non_cached * input_cost) + (cached_tokens * cached_cost) + (output_tokens * output_cost)
            total_spend += cost
            
            print(f"{model} Cost: {cost:.4f} | Total: {total_spend:.4f}")
            return _extract_output_text_from_responses(completion)

        return None
    except Exception as e:
        print(f"Error calling OpenAI API: {str(e)}")
        return None

# ----------------------------- File Utilities -----------------------------
def get_file_content(file_path: str) -> str:
    """Read file content with encoding fallback."""
    ext = Path(file_path).suffix.lower().lstrip(".")
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            if ext == "ipynb":
                nb = json.load(f)
                return "\n".join(["\n".join(c.get("source", [])) for c in nb["cells"] if c.get("cell_type") == "code"])
            return f.read()
    except UnicodeDecodeError:
        with open(file_path, "r", encoding="latin-1") as f:
            return f.read()

def get_file_type(file_path: str) -> str:
    """Return descriptive label for file extension."""
    ext = Path(file_path).suffix.lower().lstrip(".")
    mapping = {"py": "Python", "sql": "SQL", "ipynb": "Jupyter"}
    return mapping.get(ext, f"{ext} file")

def generate_export_path(script_path: str) -> str:
    """Generates a timestamped file path."""
    directory, file_name = os.path.split(script_path)
    name, ext = os.path.splitext(file_name)
    ts = datetime.datetime.now().strftime("%Y%m%d%H%M")
    
    # Handle existing timestamps to avoid stacking them
    name = re.sub(r"_(\d{12})$|_(\d{8})$", "", name)
    return os.path.join(directory, f"{name}_{ts}{ext}")

def write_content_to_file(file_path: str, content: str) -> None:
    """Writes content to disk."""
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)

def strip_existing_headers(code_text: str, target_ext: str) -> str:
    """
    Removes leading comments and whitespace from a script so that a 
    new header can be cleanly prepended without duplication of legacy notes.
    """
    ext = target_ext.lower().lstrip(".")
    if ext == "py":
        # Python: Stop at imports, defs, classes, or variable assignments
        starter = r"^\s*(import|from|class|def|[a-zA-Z_]\w*\s*=)"
    else:
        # SQL: Stop at DECLARE, BEGIN, CREATE, SELECT, etc.
        starter = r"^\s*(declare|begin|create|with|select|update|insert|merge|delete)"
    
    starter_regex = re.compile(starter, re.IGNORECASE)
    lines = code_text.splitlines()
    content_start_idx = 0
    
    for i, line in enumerate(lines):
        if starter_regex.search(line):
            content_start_idx = i
            break
            
    return "\n".join(lines[content_start_idx:])

# ----------------------------- Markdown & Sanitization -----------------------------
def extract_last_code_block(md: str) -> Tuple[Optional[str], Optional[str]]:
    """Extracts the last fenced code block."""
    pattern = re.compile(r"```([a-zA-Z0-9_+\-]*)\n(.*?)\n```", re.DOTALL)
    blocks = pattern.findall(md or "")
    if not blocks: return None, None
    return blocks[-1][1], blocks[-1][0].strip().lower()

def ensure_header_commented(code_text: str, target_ext: str) -> str:
    """Ensures prose is commented based on language."""
    ext = target_ext.lower().lstrip(".")
    token = "#" if ext == "py" else "--"
    
    # Identify code starters to stop commenting
    if ext == "py":
        starter = r"^\s*(import|from|class|def|if\s+__name__)"
    else:
        starter = r"^\s*(declare|begin|create|with|select|update|insert|merge|delete)"
    
    starter_regex = re.compile(starter, re.IGNORECASE)
    lines = code_text.splitlines()
    out = []
    seen_code = False
    
    for line in lines:
        if not seen_code and line.strip() and not starter_regex.search(line):
            if not line.lstrip().startswith(token):
                out.append(f"{token} {line}")
            else:
                out.append(line)
        else:
            if starter_regex.search(line): seen_code = True
            out.append(line)
    return "\n".join(out)

# ----------------------------- Orchestration -----------------------------
def two_step_generate(
    script_path: str,
    prompt_step1_path: str,
    prompt_step2_path: str,
    model_step1: str = "gpt-5-mini",
    model_step2: str = "gpt-5-mini",
    reasoning_effort_step1: Optional[str] = "high",
    reasoning_effort_step2: Optional[str] = "low",
) -> str:
    """
    Pipeline:
      1) Step 1 (Builder): Generates FULL code logic. Saved to disk immediately.
      2) Clean Step 1 code (removes original user comments at the very top).
      3) Step 2 (Auditor): Receives the clean code. Its prompt forces it to output 
         the New Header + the Clean Code in a single block.
      4) Overwrites the exact same file from Step 1 with the final full script.
    """
    print("[Runner!] Starting 2-step generation pipeline...")
    export_file_path = generate_export_path(script_path)
    target_ext = Path(script_path).suffix or ".sql"

    # Load artifacts
    script_text = get_file_content(script_path)
    step1_system = get_file_content(prompt_step1_path)
    step2_system = get_file_content(prompt_step2_path)

    # ---- Step 1: Builder (Full Logic) ----
    print(f"[Step1] Generating code logic with {model_step1}...")
    msg1 = [{"role": "system", "content": step1_system}, {"role": "user", "content": script_text}]
    draft_raw = callgpt(msg1, model=model_step1, reasoning_effort=reasoning_effort_step1)
    
    if not draft_raw: raise RuntimeError("Step 1 failed.")
    
    step1_code, _ = extract_last_code_block(draft_raw)
    step1_code = step1_code or draft_raw

    # Save Step 1 immediately
    write_content_to_file(export_file_path, step1_code)
    print(f"[Step1] Saved raw logic to disk. Length: {len(step1_code)} chars.")

    # ---- Clean Step 1 Code for Step 2 ----
    # This removes legacy top comments so the AI can place its new header cleanly
    clean_step1_code = strip_existing_headers(step1_code, target_ext)

    # ---- Step 2: Red Team (Header + Code) ----
    print(f"[Step2] Generating final documentation header and formatting with {model_step2}...")
    user_intent = f"ORIGINAL REQUEST:\n{script_text[:1500]}..."
    
    msg2 = [
        {"role": "system", "content": step2_system},
        {
            "role": "user", 
            "content": (
                f"{user_intent}\n\n"
                f"CODE PRODUCED FROM STEP 1 (Cleaned):\n{clean_step1_code}\n\n"
                "INSTRUCTION: Per your system prompt, generate the Standardized Documentation Header "
                "followed IMMEDIATELY by the exact code provided above. Output both together in a single code block."
            )
        }
    ]
    final_raw = callgpt(msg2, model=model_step2, reasoning_effort=reasoning_effort_step2)
    
    if not final_raw:
        print(f"[Step2][ERROR] Step 2 failed. Initial Step 1 code is preserved safely at: {export_file_path}")
        raise RuntimeError("Step 2 failed.")

    # Extract the final completed script (Header + Code) from Step 2's response
    final_script, _ = extract_last_code_block(final_raw)
    final_script = final_script or final_raw
    final_script = ensure_header_commented(final_script, target_ext)

    # ---- OVERWRITE FILE ----
    # By saving to export_file_path again, we only maintain one file, overwriting Step 1's draft.
    write_content_to_file(export_file_path, final_script.strip())
    print(f"\n[Runner] Final complete script successfully generated at:\n{export_file_path}")
    
    return final_script.strip()

if __name__ == "__main__":
    try:
        script_path = r"c:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\MillenniumFalcon\get_half_grade_20260302.sql"
        prompt_1 = r"C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\BitBucket\tank\gist\prompt\create_code.md"
        prompt_2 = r"C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\BitBucket\tank\gist\prompt\create_slopdoc_header.md"

        two_step_generate(
            script_path=script_path,
            prompt_step1_path=prompt_1,
            prompt_step2_path=prompt_2
        )
    except Exception as e:
        print(f"Pipeline Error: {str(e)}")
