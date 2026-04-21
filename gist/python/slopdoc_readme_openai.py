# *   **Work Summaries: `NiimaOutpost`**
#     In Star Wars, Niima Outpost is the settlement on Jakku where the Falcon was parked and stripped for parts before being retired to the graveyard.
#     This folder serves the same purpose: it’s where I "strip" the essential summary notes from my finished scripts to log them in ServiceNow before they are officially archived.
#
import openai
import os
import re
import json
import csv
import datetime
from typing import List, Dict, Optional

# ----------------------------- Metrics / Costs -----------------------------
input_tokens: int = 0
output_tokens: int = 0
total_spend: float = 0.0

ALLOWED_REASONING_EFFORT = {"low", "medium", "high"}

def _validate_reasoning_effort(reasoning_effort: Optional[str]) -> Optional[str]:
    """
    Normalize and validate reasoning effort for GPT-5 family models.
    """
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
    """
    Robustly extract text from Azure Responses API payloads.
    Prefers `output_text`, then walks `output[*].content[*].text`, then legacy access.
    """
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
    """
    Azure OpenAI caller supporting:
      - chat.completions for 'gpt-4.1'
      - responses API for 'gpt-5-mini' / 'gpt-5' with optional reasoning
    """
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
                max_tokens=16000,  # chat.completions
                top_p=1,
                frequency_penalty=0.0,
                presence_penalty=0.0,
                stop=None,
            )
            try:
                usage = completion.usage
                input_tokens = usage.input_tokens
                output_tokens = usage.output_tokens
            except Exception:
                input_tokens = 0
                output_tokens = 0
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
                max_output_tokens=120000, # max is 128k
                reasoning={"effort": effort} if effort else None,
                text={"verbosity": "medium"},
                previous_response_id=previous_response_id,
            )

            usage = completion.usage
            cached_tokens = 0
            try:
                cached_tokens = usage.input_tokens_details.cached_tokens
            except Exception:
                pass
 
            input_tokens = usage.input_tokens
            output_tokens = usage.output_tokens

            tks = 1_000_000
            if model == "gpt-5-mini":
                cached_cost = 0.025 / tks
                input_cost = 0.25 / tks
                output_cost = 2.00 / tks
            elif model == "gpt-4.1":
                cached_cost = 0.125 / tks
                input_cost = 1.25 / tks
                output_cost = 10.00 / tks
            else:  # gpt-5
                cached_cost = 0.125 / tks
                input_cost = 1.25 / tks
                output_cost = 10.00 / tks

            try:
                reasoning_tokens = usage.output_tokens_details.reasoning_tokens
                print(
                    "Reasoning Tokens:", reasoning_tokens,
                    "Input Tokens:", input_tokens,
                    "; Output Tokens:", output_tokens,
                    "Cached Tokens", cached_tokens,
                )
            except Exception:
                print(
                    "Input Tokens:", input_tokens,
                    "; Output Tokens:", output_tokens,
                    "Cached Tokens", cached_tokens,
                )

            non_cached = input_tokens - cached_tokens
            cost = (non_cached * input_cost) + (cached_tokens * cached_cost) + (output_tokens * output_cost)
            total_spend += cost
            print(model, "*** Cost ***", cost, "total_spend", total_spend)

            return _extract_output_text_from_responses(completion)

        else:
            print(f"Unsupported model: {model}")
            return None

    except Exception as e:
        print(f"Error calling OpenAI API: {str(e)}")
        return None

def get_file_content(file_path):
    """
    Reads content from various file types including .vtt, .sql, .md, .txt, .py, .ipynb, and .csv files.
    
    Args:
        file_path (str): The full path to the file
        
    Returns:
        str: The content of the file
        
    Raises:
        FileNotFoundError: If the file doesn't exist
        IOError: If there's an error reading the file
        ValueError: If the file type is not supported
    """
    file_extension = file_path.lower().split('.')[-1]

    # --- Helpers (scoped to this function) ---
    def _read_text(path: str, encoding: str = "utf-8") -> str:
        try:
            with open(path, 'r', encoding=encoding) as f:
                return f.read()
        except UnicodeDecodeError:
            with open(path, 'r', encoding='latin-1') as f:
                return f.read()

    def _read_csv(path: str) -> str:
        try:
            with open(path, 'r', encoding='utf-8', newline='') as f:
                rdr = csv.reader(f)
                return '\n'.join([','.join(row) for row in rdr])
        except UnicodeDecodeError:
            with open(path, 'r', encoding='latin-1', newline='') as f:
                rdr = csv.reader(f)
                return '\n'.join([','.join(row) for row in rdr])

    def _parse_vtt_to_text(vtt: str) -> str:
        # Remove WEBVTT header and NOTE blocks; drop cue ids and timestamps; keep spoken text.
        lines = vtt.splitlines()
        out = []
        in_note = False
        ts_re = re.compile(r"\d{2}:\d{2}:\d{2}\.\d{3}\s*-->\s*\d{2}:\d{2}:\d{2}\.\d{3}")
        cue_id_re = re.compile(r"^\s*\d+\s*$")

        for raw in lines:
            line = raw.strip("\ufeff")
            if not line:
                out.append("")
                continue
            up = line.strip().upper()

            if up.startswith("WEBVTT"):
                continue
            if up.startswith("NOTE"):
                in_note = True
                continue
            if in_note:
                if not line.strip():
                    in_note = False
                continue
            if cue_id_re.match(line):
                continue
            if ts_re.search(line):
                continue

            out.append(line)

        text = "\n".join(out)
        text = re.sub(r"\n{3,}", "\n\n", text).strip()
        return text

    try:
        if file_extension == 'ipynb':
            try:
                with open(file_path, 'r', encoding='utf-8') as file:
                    notebook = json.load(file)
            except UnicodeDecodeError:
                with open(file_path, 'r', encoding='latin-1') as file:
                    notebook = json.load(file)
            content = []
            for cell in notebook.get('cells', []):
                if cell.get('cell_type') == 'code':
                    content.extend(cell.get('source', []))
            return '\n'.join(content)

        elif file_extension in ['sql', 'md', 'txt', 'py']:
            return _read_text(file_path)

        elif file_extension == 'csv':
            return _read_csv(file_path)

        elif file_extension == 'vtt':
            raw = _read_text(file_path)
            return _parse_vtt_to_text(raw)

        else:
            raise ValueError(f"Unsupported file type: .{file_extension}")

    except FileNotFoundError:
        raise FileNotFoundError(f"The file at {file_path} was not found.")
    except json.JSONDecodeError:
        raise IOError("Error reading the Jupyter notebook: Invalid format")
    except IOError as e:
        raise IOError(f"Error reading the file: {str(e)}")
    except Exception as e:
        raise IOError(f"Unexpected error while reading file: {str(e)}")
    
import os
import re
import unicodedata
import datetime

WINDOWS_RESERVED_NAMES = {
    "con", "prn", "aux", "nul",
    *{f"com{i}" for i in range(1, 10)},
    *{f"lpt{i}" for i in range(1, 10)},
}

def _sanitize_filename_component(
    text: str,
    *,
    max_len: int = 50,
    delimiter: str = "_",
    lowercase: bool = True
) -> str:
    """
    Sanitize a filename *component* by:
        - Normalizing to ASCII (drop non-ASCII)
        - Replacing non-alphanumeric sequences with a delimiter
        - Lowercasing (optional)
        - Trimming to max_len
        - Removing leading/trailing delimiters, dots, and spaces
        - Avoiding Windows reserved names

    Returns a safe filename component (without extension).
    """
    if not text:
        return "untitled"

    # 1) Normalize to ASCII (drop diacritics and non-ASCII)
    #    e.g., “Tučker” -> "Tucker"
    text = unicodedata.normalize("NFKD", text)
    text = text.encode("ascii", "ignore").decode("ascii")

    # Optional case-fold
    if lowercase:
        text = text.lower()

    # 2) Replace any non-alphanumeric sequence with delimiter
    #    (removes commas, parentheses, symbols, etc.)
    text = re.sub(r"[^a-zA-Z0-9]+", delimiter, text)

    # 3) Collapse repeated delimiters
    if delimiter:
        repeated = re.escape(delimiter)
        text = re.sub(rf"{repeated}+", delimiter, text)

    # 4) Strip delimiters, dots, spaces from ends (Windows hates trailing dot/space)
    text = text.strip(f"{delimiter} .")

    # 5) Avoid empty result
    if not text:
        text = "untitled"

    # 6) Avoid Windows reserved device names (case-insensitive)
    if text.lower() in WINDOWS_RESERVED_NAMES:
        text = f"{text}{delimiter}file"

    # 7) Enforce max length
    if max_len and len(text) > max_len:
        text = text[:max_len].rstrip(f"{delimiter} .")

    # 8) Final safety: nothing but alnum and delimiter remains; if empty, fallback
    if not text:
        text = "untitled"

    return text


def write_markdown_output(
    output_dir: str,
    input_file_path: str,
    ai_markdown: str,
    *,
    max_file_len: int = 50,       # ← your 50-char cap (adjustable)
    delimiter: str = "_",            # ← use "_" (or "-" if you prefer)
    lowercase: bool = True           # ← set False to preserve case
) -> str:
    """
    Write the AI output to a new Markdown file in the specified directory, using:
        sanitized_filename_YYYYMMDD.md

    Args:
        output_dir: Target directory where file notes are stored
        input_file_path: Original source path used to derive the file name
        ai_markdown: Markdown content to write
        max_file_len: Max length for the file name segment
        delimiter: Delimiter used between tokens of the file name
        lowercase: Lowercase the file name segment

    Returns:
        Full path to the written file
    """
    # Ensure directory exists
    if not os.path.isdir(output_dir):
        os.makedirs(output_dir, exist_ok=True)

    # Extract original stem (without extension)
    stem = os.path.splitext(os.path.basename(input_file_path))[0]

    # Sanitize file name
    file_name = _sanitize_filename_component(
        stem,
        max_len=max_file_len,
        delimiter=delimiter,
        lowercase=lowercase
    )

    # Append date (YYYYMMDD)        
    file_dt = datetime.datetime.fromtimestamp(os.path.getmtime(input_file_path))
    current_date = file_dt.strftime("%Y%m%d")

    dated_name = f"{file_name}{delimiter}{"README"}"

    # Windows does not allow trailing dots/spaces in filenames
    dated_name = dated_name.rstrip(" .")

    out_path = os.path.join(output_dir, f"{dated_name}.md")

    # Write file
    try:
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(ai_markdown or "")
    except Exception as exc:
        raise IOError(f"Failed to write output file '{out_path}': {exc}") from exc

    return out_path

# Main execution
if __name__ == "__main__":
    try:
        # Update paths as needed
        output_dir = r"C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\NiimaOutpost" ## SAVE LOCATION
        system_path = r"C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\BitBucket\tank\gist\prompt\create_slopdoc_readme.md" ## CREATE FULL README
        
        system_prompt = get_file_content(system_path)
        input_path = r"C:\Users\wgriffith2\Desktop\Golem\chats\dates_tables_20260326.sql"

        file_dt = datetime.datetime.fromtimestamp(os.path.getmtime(input_path))
        file_timestamp = file_dt.strftime("%Y%m%d%H%M")
        input_text = get_file_content(input_path)
        input_text += f"The file date is: {file_timestamp}. This file owner is WGRIFFITH2. Here are the file notes: {input_text}"

        print('Calling AI model to create README for:', input_path)

        # Build messages and call the model
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": input_text}
        ]
        
        response = callgpt(
            messages=messages,
            model="gpt-5-mini",
            reasoning_effort="medium")  # 'low' | 'medium' | 'high'

        if response:
            print(response)
            # Write a NEW markdown file to the file Notes directory
            out_path = write_markdown_output(output_dir=output_dir, input_file_path=input_path, ai_markdown=response)
            # Replace the faulty print with an f-string (the braces created a set)
            print("\n" + "=" * 60)
            print(f"Saved:\n{out_path}")
            print("\n" + "=" * 60)
            print("README Created!")
            print("=" * 60)
        else:
            print("Failed to generate summary.")
    except Exception as e:
        print(f"An error occurred: {str(e)}")
