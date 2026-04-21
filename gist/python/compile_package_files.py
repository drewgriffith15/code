
import os
from pathlib import Path
from typing import List, Optional

def build_deployment_script(input_directory: str, output_filepath: str, file_list: Optional[List[str]] = None) -> None:
    """
    Merges multiple Oracle PL/SQL files into a single deployment script.
    Saves the final output to the user's Downloads folder.
    """
    input_dir = Path(input_directory)
    output_file = Path(output_filepath)
    
    if not input_dir.exists() or not input_dir.is_dir():
        raise NotADirectoryError(f"Directory not found: {input_directory}")

    # Auto-discover files if list is not provided
    if not file_list:
        all_files = []
        # Target common Oracle file extensions
        for ext in ['.pks', '.sql', '.pkb', '.prc', '.fnc']:
            all_files.extend(input_dir.glob(f"*{ext}"))
            all_files.extend(input_dir.glob(f"*{ext.upper()}"))
            
        # Deduplicate and sort (Specs (.pks) -> Scripts/Procs (.sql/.prc) -> Bodies (.pkb))
        priority = {'.pks': 1, '.sql': 2, '.prc': 2, '.fnc': 2, '.pkb': 3}
        all_files = list(set(all_files))
        all_files.sort(key=lambda f: (priority.get(f.suffix.lower(), 99), f.name))
        files_to_process = all_files
    else:
        files_to_process = [input_dir / fname for fname in file_list]

    if not files_to_process:
        print("No files found to merge.")
        return

    # Merge logic
    with open(output_file, 'w', encoding='utf-8') as outfile:
        outfile.write("-- =====================================================================\n")
        outfile.write(f"-- MASTER DEPLOYMENT SCRIPT: {os.path.basename(output_filepath)}\n")
        outfile.write("-- =====================================================================\n\n")

        for file_path in files_to_process:
            if not file_path.exists():
                continue

            with open(file_path, 'r', encoding='utf-8') as infile:
                content = infile.read().strip()

            outfile.write(f"-- {'='*65}\n")
            outfile.write(f"-- SOURCE: {file_path.name}\n")
            outfile.write(f"-- {'='*65}\n")
            outfile.write(content)
            
            # Critical check: Ensure every file ends with a '/' so Oracle executes the block
            if not content.endswith('/'):
                outfile.write("\n/")
                
            outfile.write("\n\n")
            print(f"Merged: {file_path.name}")

    print(f"\nSuccess! File generated at: {output_file}")


if __name__ == "__main__":
    # --- DYNAMIC PATH LOGIC ---
    
    # Identify the Downloads folder dynamically for any Windows/Mac/Linux user
    # Note: We must join the directory path with a filename, otherwise open() fails
    downloads_path = os.path.join(os.path.expanduser('~'), 'Downloads')
    final_output = os.path.join(downloads_path, 'master_deployment_script.sql')
    
    # Location where your individual .sql or .pks files are stored
    SOURCE_DIR = r"C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\SVN\sql\ADS_ETL"

    # --- EXECUTION ---
    build_deployment_script(SOURCE_DIR, final_output)