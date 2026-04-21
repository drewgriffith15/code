import os
from pathlib import Path
from typing import List, Tuple
import codecs
import json
from datetime import datetime

def find_files(start_path: str, file_extensions: List[str]) -> List[Tuple[Path, float]]:
    """
    Recursively find files with specified extensions from the start path.
    Also gets the modification time for each file for sorting later.
    
    Args:
        start_path (str): Directory path to start the search from
        file_extensions (List[str]): List of file extensions to search for
        
    Returns:
        List[Tuple[Path, float]]: List of tuples with path and modification time
    """
    matching_files: List[Tuple[Path, float]] = []
    start_path = Path(start_path)
    
    try:
        for ext in file_extensions:
            for path in start_path.rglob(f"*{ext}"):
                try:
                    mod_time = path.stat().st_mtime
                    matching_files.append((path, mod_time))
                except Exception as e:
                    print(f"Error accessing file {path}: {e}")
    except Exception as e:
        print(f"Error accessing directory {start_path}: {e}")
        
    return matching_files

def read_ipynb_content(file_path: Path) -> str:
    """
    Extract text content from Jupyter notebook files.
    
    Args:
        file_path (Path): Path to the .ipynb file
        
    Returns:
        str: Extracted content from notebook cells
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as file:
            notebook = json.load(file)
            
        content = []
        if 'cells' in notebook:
            for cell in notebook['cells']:
                if 'source' in cell and isinstance(cell['source'], list):
                    cell_content = ''.join(cell['source'])
                    content.append(cell_content)
        
        return '\n'.join(content)
    except Exception as e:
        print(f"Error reading notebook {file_path}: {e}")
        return ""

def try_different_encodings(file_path: Path) -> Tuple[bool, str, str]:
    """
    Try different encodings to read the file.
    
    Args:
        file_path (Path): Path to the file to read
        
    Returns:
        Tuple[bool, str, str]: Success flag, file content, and encoding used
    """
    encodings = [
        'utf-8', 'latin-1', 'cp1252', 'iso-8859-1',
        'ascii', 'utf-16', 'utf-32'
    ]
    
    for encoding in encodings:
        try:
            with codecs.open(file_path, 'r', encoding=encoding) as file:
                content = file.read()
                return True, content, encoding
        except Exception:
            continue
            
    return False, "", ""

def search_file_content(file_path: Path, keyword: str) -> List[Tuple[int, str]]:
    """
    Search for keyword in file content and return matching lines with line numbers.
    
    Args:
        file_path (Path): Path to the file to search
        keyword (str): Keyword to search for
        
    Returns:
        List[Tuple[int, str]]: List of tuples containing line number and matching line
    """
    matches: List[Tuple[int, str]] = []
    keyword = keyword.lower()
    
    if file_path.suffix.lower() == '.ipynb':
        content = read_ipynb_content(file_path)
        if content:
            try:
                for i, line in enumerate(content.splitlines(), 1):
                    if keyword in line.lower():
                        matches.append((i, line.strip()))
            except Exception:
                # Silently skip unreadable/invalid notebook content
                return matches
        return matches

    success, content, encoding = try_different_encodings(file_path)

    if not success:
        # Silently skip files that cannot be read with supported encodings
        return matches

    for i, line in enumerate(content.splitlines(), 1):
        if keyword in line.lower():
            matches.append((i, line.strip()))    
    return matches

def format_modification_time(timestamp: float) -> str:
    """
    Format a timestamp into a human-readable date/time string.
    
    Args:
        timestamp (float): Modification time as Unix timestamp
        
    Returns:
        str: Formatted date/time string
    """
    dt = datetime.fromtimestamp(timestamp)
    return dt.strftime("%Y-%m-%d %H:%M:%S")

def main() -> None:
    """
    Main function to search files for a keyword, sorted by most recent modification time.
    """
    if not file_location:
        print("Error: Please specify a file location")
        return
    
    if not os.path.exists(file_location):
        print(f"Error: Path '{file_location}' does not exist")
        return
    
    file_extensions = ['.sql', '.md', '.txt', '.py', '.ipynb']
    
    matching_files_with_times = find_files(file_location, file_extensions)
    
    if not matching_files_with_times:
        print(f"No matching files found in {file_location}")
        return
    
    # Sort files by modification time (descending: most recent first)
    sorted_files = sorted(matching_files_with_times, key=lambda x: x[1], reverse=True)
    
    print(f"Found {len(sorted_files)} files to search (sorted by most recent first)")
    
    found_matches = False
    
    for file_path, mod_time in sorted_files:
        filename_matches = search_keyword.lower() in file_path.name.lower()
        content_matches = search_file_content(file_path, search_keyword)
        
        if filename_matches or content_matches:
            found_matches = True
            mod_time_str = format_modification_time(mod_time)
            print(f"\nFile: {file_path} (Modified: {mod_time_str})")
            
            if filename_matches:
                print("  [Matched in filename]")
            
            if content_matches:
                print("  Matching lines:")
                for line_num, line in content_matches:
                    display_line = line[:200] + "..." if len(line) > 200 else line
                    print(f"    Line {line_num}: {display_line}")
    
    if not found_matches:
        print(f"\nNo matches found for '{search_keyword}'")

# User input variables
file_location = r"C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\Jakku"
search_keyword = "WHTEST"

if __name__ == "__main__":
    main()