### My Star Wars Themed Workflow Explained
# My folder structure is organized thematically around the journey of the Millennium Falcon to tell a story about my development process:
# *   **Active Dev: `MillenniumFalcon`**
#     This folder contains all my current projects. It's the ship I'm actively flying, tinkering with, and using to navigate the "Kessel Run" of daily development tasks. It’s fast, a bit chaotic, and where all the hands-on work gets done.
# *   **Work Summaries: `NiimaOutpost`**
#     In Star Wars, Niima Outpost is the settlement on Jakku where the Falcon was parked and stripped for parts before being retired to the graveyard. This folder serves the same purpose: it’s where I "strip" the essential summary notes from my finished scripts to log them in ServiceNow before they are officially archived.
# *   **Archive: `Jakku`**
#     This is the final resting place for retired projects. Just like the massive ship graveyard on Jakku where the Falcon was left, this folder holds all the old, completed work that is no longer in active development but is kept for historical purposes.#
import openai
import os
import json
import csv
import datetime
import shutil
from typing import List, Dict, Optional, Tuple
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


def get_file_content(file_path: str) -> str:
    """
    Reads content from various file types including .sql, .md, .txt, .py, .ipynb, and .csv files.
    """
    file_extension = file_path.lower().split('.')[-1]
    try:
        if file_extension == 'ipynb':
            with open(file_path, 'r', encoding='utf-8') as file:
                notebook = json.load(file)
                content = []
                for cell in notebook.get('cells', []):
                    if cell.get('cell_type') == 'code':
                        content.extend(cell.get('source', []))
                return '\n'.join(content)
        elif file_extension in ['sql', 'md', 'txt', 'py']:
            with open(file_path, 'r', encoding='utf-8') as file:
                return file.read()
        elif file_extension == 'csv':
            with open(file_path, 'r', encoding='utf-8', newline='') as file:
                reader = csv.reader(file)
                return '\n'.join([','.join(row) for row in reader])
        else:
            raise ValueError(f"Unsupported file type: .{file_extension}")
    except UnicodeDecodeError:
        with open(file_path, 'r', encoding='latin-1') as file:
            return file.read()
    except Exception as e:
        return f"Error reading file: {e}"


def compile_and_archive_work_notes() -> Optional[str]:
    """
    Deletes temp '.~sql' files from MillenniumFalcon, moves allowed files to Jakku,
    and compiles their contents into a timestamped Markdown file in NiimaOutpost.
    """
    falcon_folder = r'C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\MillenniumFalcon'
    jakku_folder = r'C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\Jakku'
    niima_folder = r'C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\NiimaOutpost'

    for folder in [falcon_folder, jakku_folder, niima_folder]:
        if not os.path.isdir(folder):
            os.makedirs(folder, exist_ok=True)

    allowed_exts = ['md', 'txt', 'sql', 'py', 'ipynb', 'csv']
    files_to_compile: List[Tuple[str, float]] = []

    try:
        with os.scandir(falcon_folder) as it:
            for entry in it:
                if not entry.is_file():
                    continue
                name_lc = entry.name.lower()

                # Delete temp files
                if name_lc.endswith('.~sql'):
                    try:
                        os.remove(entry.path)
                        print(f"Deleted temp file: {entry.path}")
                    except Exception as e:
                        print(f"Error deleting temp file: {e}")
                    continue

                # Move allowed files
                ext = name_lc.rsplit('.', 1)[-1]
                if ext in allowed_exts:
                    try:
                        destination_path = os.path.join(jakku_folder, entry.name)
                        shutil.move(entry.path, destination_path)
                        modification_time = os.path.getmtime(destination_path)
                        files_to_compile.append((destination_path, modification_time))
                        print(f"Moved file: {entry.path} → {destination_path}")
                    except Exception as e:
                        print(f"Error moving file: {e}")
    except Exception as e:
        print(f"Error scanning source folder: {e}")
        return None

    files_to_compile.sort(key=lambda x: x[1])
    if not files_to_compile:
        print("No relevant files found.")
        return None

    now = datetime.datetime.now()
    output_filename = f"worknotes_{now.strftime('%Y%m%d%H%M')}.md"
    output_filepath = os.path.join(niima_folder, output_filename)

    try:
        with open(output_filepath, 'w', encoding='utf-8') as outfile:
            for file_path, _ in files_to_compile:
                content = get_file_content(file_path)
                outfile.write(f"\n--- Content from: {os.path.basename(file_path)} ---\n\n")
                outfile.write(content)
                outfile.write('\n\n')
        print(f"COMPILED WORK NOTES (below):\n{output_filepath}")
        return output_filepath
    except Exception as e:
        print(f"Error writing combined file: {e}")
        return None


def update_markdown_with_summary(file_path: str, summary: str) -> bool:
    """
    Prepends AI-generated summary to the compiled Markdown file.
    """
    try:
        original_content = get_file_content(file_path)
        updated_content = f"{summary}\n\n{original_content}"
        with open(file_path, 'w', encoding='utf-8') as file:
            file.write(updated_content)
        return True
    except Exception as e:
        print(f"Error updating markdown file: {e}")
        return False


# Main execution
if __name__ == "__main__":
    try:
        worknotes_path = compile_and_archive_work_notes()
        if not worknotes_path:
            print("No worknotes file created. Exiting.")
            exit(1)

        system_path = r"C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\BitBucket\tank\gist\prompt\create_slopdoc_work_notes.md"
        system_prompt = get_file_content(system_path)
        system_prompt += f"The current date is: {datetime.datetime.now().strftime('%Y%m%d%H%M')}. My username is WGRIFFITH2."

        input_text = get_file_content(worknotes_path)
        if not input_text.strip():
            print("Compiled file is empty. Skipping AI summary.")
            exit(0)

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": input_text}
        ]

        print("Calling AI to create worknotes summary...")
        response = callgpt(messages)
        if response:
            if update_markdown_with_summary(worknotes_path, response):
                print("Summary added successfully.")
            else:
                print("Failed to update markdown file.")
        else:
            print("Failed to generate summary.")

    except Exception as e:
        print(f"An error occurred: {e}")
