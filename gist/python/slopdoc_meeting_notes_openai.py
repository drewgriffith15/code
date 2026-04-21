# could you figure out why the error is happening at the end? the original output should be appending to the bottom of the output file. 
# ============================================================
# An error occurred: can only concatenate str (not "set") to str
###
# *   **Meeting Notes: `Coruscant`**
#     This folder holds all high-level planning and decision-making documents. Like the galactic capital Coruscant, this is where strategy is discussed, political maneuvering happens (navigating project requirements), and the blueprints for future missions are laid out.
#
import openai
import os
import re
import json
import csv
import datetime
from typing import List, Dict, Optional
from dotenv import load_dotenv
from pathlib import Path

env_path = os.getenv('DOTENV')
if env_path and Path(env_path).exists():
    load_dotenv(env_path, override=True)

# Global variables for tracking token usage and cost
input_tokens: int = 0
output_tokens: int = 0
total_spend: float = 0.0

def callgpt(
    messages: List[Dict[str, str]],
    model: str = "gpt-5-mini",
    reasoning_effort: Optional[str] = 'low', # Note: GPT-5 family supports reasoning. Valid values: 'low', 'medium', 'high'.
    previous_response_id: Optional[str] = None
) -> Optional[str]:
    """
    Calls the Azure OpenAI API to generate a response based on the provided messages.
    Supports both GPT-4.1 and GPT-5 models with cost tracking and reasoning effort.
    """
    global input_tokens, output_tokens, total_spend

    endPoint = 'AZURE_END_POINT'
    apiKey = 'AZURE_OPENAI_KEY'

    try:
        if model == "gpt-4.1":
            client = openai.AzureOpenAI(
                azure_endpoint=os.getenv(endPoint),
                api_key=os.getenv(apiKey),
                api_version="2025-01-01-preview"
            )
            completion = client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=0,
                max_tokens=128000
            )
            usage = completion.usage
            input_tokens = usage.input_tokens
            output_tokens = usage.output_tokens
            return completion.choices[0].message.content

        elif model in ["gpt-5-mini", "gpt-5"]:
            client = openai.AzureOpenAI(
                azure_endpoint=os.getenv(endPoint),
                api_key=os.getenv(apiKey),
                api_version="2025-04-01-preview"
            )
            completion = client.responses.create(
                model=model,
                input=messages,
                max_output_tokens=128000,
                reasoning={'effort': reasoning_effort} if reasoning_effort else None,
                text={'verbosity': 'medium'},
                previous_response_id=previous_response_id
            )
            usage = completion.usage
            cached_tokens = getattr(usage.input_tokens_details, 'cached_tokens', 0)
            input_tokens = usage.input_tokens
            output_tokens = usage.output_tokens

            tks = 1000000
            if model == 'gpt-5-mini':
                cachedCost = .025 / tks
                inputCost = .25 / tks
                outputCost = 2.00 / tks
            else:
                cachedCost = .125 / tks
                inputCost = 1.25 / tks
                outputCost = 10.00 / tks

            non_cached_tokens = input_tokens - cached_tokens
            cost = (non_cached_tokens * inputCost) + (cached_tokens * cachedCost) + (output_tokens * outputCost)
            total_spend += cost
            print(model, '*** Cost ***', cost, 'total_spend', total_spend)

            try:
                return completion.output[1].content[0].text
            except Exception:
                return None

        else:
            print(f"Unsupported model: {model}")
            return None

    except Exception as e:
        print(f"Error calling OpenAI API: {str(e)}")
        return None


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
    max_meeting_len: int = 50,       # ← your 50-char cap (adjustable)
    delimiter: str = "_",            # ← use "_" (or "-" if you prefer)
    lowercase: bool = True           # ← set False to preserve case
) -> str:
    """
    Write the AI output to a new Markdown file in the specified directory, using:
        sanitized_meetingname_YYYYMMDD.md

    Args:
        output_dir: Target directory where meeting notes are stored
        input_file_path: Original source path used to derive the meeting name
        ai_markdown: Markdown content to write
        max_meeting_len: Max length for the meeting name segment
        delimiter: Delimiter used between tokens of the meeting name
        lowercase: Lowercase the meeting name segment

    Returns:
        Full path to the written file
    """
    # Ensure directory exists
    if not os.path.isdir(output_dir):
        os.makedirs(output_dir, exist_ok=True)

    # Extract original stem (without extension)
    stem = os.path.splitext(os.path.basename(input_file_path))[0]

    # Sanitize meeting name
    meeting_name = _sanitize_filename_component(
        stem,
        max_len=max_meeting_len,
        delimiter=delimiter,
        lowercase=lowercase
    )

    # Append date (YYYYMMDD)        
    file_dt = datetime.datetime.fromtimestamp(os.path.getmtime(input_file_path))
    current_date = file_dt.strftime("%Y%m%d")

    dated_name = f"{meeting_name}{delimiter}{current_date}"

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
        output_dir = r"C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\Coruscant"
        system_path = r"C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\BitBucket\tank\gist\prompt\create_slopdoc_meeting_notes.md"
        system_prompt = get_file_content(system_path)
        input_path = r"C:\Users\wgriffith2\Downloads\Chat through the Residents Student Dashboard.vtt"

        file_dt = datetime.datetime.fromtimestamp(os.path.getmtime(input_path))
        meeting_timestamp = file_dt.strftime("%Y%m%d%H%M")
        input_text = get_file_content(input_path)
        input_text += f"The meeting date is: {meeting_timestamp}. Here are the meeting notes: {input_text}"

        print('Calling AI model to create meeting notes summary for:', input_path)

        # Build messages and call the model
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": input_text}
        ]
        
        response = callgpt(
            messages=messages,
            model="gpt-5-mini",
            reasoning_effort="high")  # 'low' | 'medium' | 'high'

        if response:
            print(response)
            # Write a NEW markdown file to the Meeting Notes directory
            out_path = write_markdown_output(output_dir=output_dir, input_file_path=input_path, ai_markdown=response)
            print("\n" + "=" * 60)
            print("Saved:\n" + {out_path}) 
            print("\n" + "=" * 60)
            print("[Main] Pipeline complete")
            print("=" * 60)
        else:
            print("Failed to generate summary.")
    except Exception as e:
        print(f"An error occurred: {str(e)}")
