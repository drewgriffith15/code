import os
import re
import sys
import time
from pathlib import Path

from dotenv import load_dotenv
from notion_client import Client

sys.path.insert(0, str(Path(__file__).parent))
from tank import query, select_finisher, get_atom, update_atom_content

load_dotenv(Path(__file__).parent.parent.parent / '.env')

NOTION_TOKEN = os.environ['NOTION_TOKEN']
CGX_PAGE_ID = os.environ.get('CGX_PAGE_ID')
if not CGX_PAGE_ID:
    print("ERROR: CGX_PAGE_ID not set in .env")
    sys.exit(1)

notion = Client(auth=NOTION_TOKEN)

NOTION_TEXT_LIMIT = 2000


def chunk_text(s):
    chunks = []
    while len(s) > NOTION_TEXT_LIMIT:
        split_at = s.rfind(' ', 0, NOTION_TEXT_LIMIT)
        if split_at == -1:
            split_at = NOTION_TEXT_LIMIT
        chunks.append(s[:split_at])
        s = s[split_at:].lstrip()
    if s:
        chunks.append(s)
    return chunks


def markdown_to_notion_blocks(text):
    blocks = []
    for line in text.splitlines():
        s = line.strip()
        if not s:
            continue
        if s.startswith('# '):
            continue
        elif s.startswith('Video URL:'):
            url = s.replace('Video URL:', '').strip()
            blocks.append({
                'object': 'block',
                'type': 'paragraph',
                'paragraph': {'rich_text': [{'type': 'text', 'text': {'content': url, 'link': {'url': url}}}]},
            })
        elif s.startswith('Source: http'):
            url = s.replace('Source:', '').strip()
            blocks.append({
                'object': 'block',
                'type': 'paragraph',
                'paragraph': {'rich_text': [{'type': 'text', 'text': {'content': url, 'link': {'url': url}}}]},
            })
        elif s.startswith('### '):
            blocks.append({
                'object': 'block',
                'type': 'heading_3',
                'heading_3': {'rich_text': [{'type': 'text', 'text': {'content': s[4:]}}]},
            })
        elif s.startswith('## '):
            blocks.append({
                'object': 'block',
                'type': 'heading_2',
                'heading_2': {'rich_text': [{'type': 'text', 'text': {'content': s[3:]}}]},
            })
        elif s.startswith('- '):
            for chunk in chunk_text(s[2:]):
                blocks.append({
                    'object': 'block',
                    'type': 'bulleted_list_item',
                    'bulleted_list_item': {'rich_text': [{'type': 'text', 'text': {'content': chunk}}]},
                })
        else:
            for chunk in chunk_text(s):
                blocks.append({
                    'object': 'block',
                    'type': 'paragraph',
                    'paragraph': {'rich_text': [{'type': 'text', 'text': {'content': chunk}}]},
                })
    return blocks


def clear_page(page_id):
    blocks = notion.blocks.children.list(page_id)
    for block in blocks['results']:
        notion.blocks.delete(block['id'])
    print(f'  Cleared {len(blocks["results"])} child blocks')


def day_number(title):
    m = re.search(r'Day\s+(\d+)', title, re.IGNORECASE)
    return int(m.group(1)) if m else 0


def _parse_workout_timing(content):
    m = re.search(r'(\d+)s?\s*Work\s*/\s*(\d+)s?\s*Rest', content, re.IGNORECASE)
    if m:
        return f'{m.group(1)}s Work / {m.group(2)}s Rest'
    return None


def _finisher_timing(f, workout_timing):
    stored = f.get('timing_pattern', '')
    if not workout_timing:
        return stored
    if 'per leg' in stored:
        return f'2 Sets per leg ({workout_timing})'
    if 'per side' in stored:
        return f'2 Sets per side ({workout_timing})'
    return f'2 Sets ({workout_timing})'


def _finisher_item(f, workout_timing):
    muscles = f['primary_muscles']
    if f.get('secondary_muscles'):
        muscles = f['primary_muscles'] + ' / ' + f['secondary_muscles']
    timing = _finisher_timing(f, workout_timing)
    return {
        'type': 'bulleted_list_item',
        'bulleted_list_item': {
            'rich_text': [
                {'type': 'text', 'text': {'content': f['name']}, 'annotations': {'bold': True}},
                {'type': 'text', 'text': {'content': f' ({f["category"]})'}},
            ],
            'children': [
                {
                    'type': 'bulleted_list_item',
                    'bulleted_list_item': {'rich_text': [{'type': 'text', 'text': {'content': f'Target: {muscles}'}}]},
                },
                {
                    'type': 'bulleted_list_item',
                    'bulleted_list_item': {'rich_text': [{'type': 'text', 'text': {'content': f'Timing: {timing}'}}]},
                },
            ],
        },
    }


def _finisher_section(f0, f1, workout_timing):
    return [
        {
            'type': 'heading_3',
            'heading_3': {'rich_text': [{'type': 'text', 'text': {'content': 'OPTIONAL GLUTES'}}]},
        },
        _finisher_item(f0, workout_timing),
        _finisher_item(f1, workout_timing),
    ]


def push_program(program_name):
    atoms = query(domain="workouts", type="workout", limit=100)
    filtered = [a for a in atoms if a.get('metadata', {}).get('program') == program_name]
    if not filtered:
        print(f'ERROR: No workouts found for program {program_name}')
        sys.exit(1)

    sorted_atoms = sorted(filtered, key=lambda a: day_number(a['title']))
    print(f'Program : {program_name} ({len(sorted_atoms)} workouts)')
    print('Clearing CGX page...')
    clear_page(CGX_PAGE_ID)

    for atom in sorted_atoms:
        title = atom['title']
        content = atom.get('content', '')
        blocks = markdown_to_notion_blocks(content)

        page_id = notion.pages.create(
            parent={'page_id': CGX_PAGE_ID},
            properties={'title': {'title': [{'type': 'text', 'text': {'content': title}}]}}
        )['id']

        for i in range(0, len(blocks), 100):
            notion.blocks.children.append(page_id, children=blocks[i:i + 100])

        f0 = select_finisher(atom['id'], offset=0)
        f1 = select_finisher(atom['id'], offset=1)
        if f0 and f1:
            workout_timing = _parse_workout_timing(content)
            notion.blocks.children.append(page_id, children=_finisher_section(f0, f1, workout_timing))

        print(f'  OK  {title}')
        time.sleep(0.35)

    print(f'\nDone. {len(sorted_atoms)} workouts live under CGX.')


def _find_notion_page_by_title(title):
    cursor = None
    while True:
        kwargs = {'block_id': CGX_PAGE_ID, 'page_size': 100}
        if cursor:
            kwargs['start_cursor'] = cursor
        resp = notion.blocks.children.list(**kwargs)
        for block in resp['results']:
            if block['type'] != 'child_page':
                continue
            if block['child_page']['title'] == title:
                return block['id']
        if resp.get('has_more'):
            cursor = resp['next_cursor']
        else:
            break
    return None


def repair_workout(atom_id, new_content=None):
    atom = get_atom(atom_id)
    if not atom:
        print(f'ERROR: Atom {atom_id} not found in Construct')
        sys.exit(1)

    if new_content is not None:
        update_atom_content(atom_id, new_content)
        atom['content'] = new_content
        print(f'  Construct updated: {atom_id}')

    title = atom['title']
    content = atom.get('content', '')

    page_id = _find_notion_page_by_title(title)
    if not page_id:
        print(f'ERROR: No Notion page found with title "{title}" under CGX page')
        sys.exit(1)

    clear_page(page_id)

    blocks = markdown_to_notion_blocks(content)
    for i in range(0, len(blocks), 100):
        notion.blocks.children.append(page_id, children=blocks[i:i + 100])

    f0 = select_finisher(atom_id, offset=0)
    f1 = select_finisher(atom_id, offset=1)
    if f0 and f1:
        workout_timing = _parse_workout_timing(content)
        notion.blocks.children.append(page_id, children=_finisher_section(f0, f1, workout_timing))

    print(f'  OK  {title} -> Notion page {page_id} repaired')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: python cgx.py <PROGRAM_NAME>')
        print('       python cgx.py repair <atom_id>')
        print('Example: python cgx.py FUEL')
        print('Example: python cgx.py repair ATOM-0361')
        sys.exit(1)
    if sys.argv[1] == 'repair':
        if len(sys.argv) != 3:
            print('Usage: python cgx.py repair <atom_id>')
            sys.exit(1)
        repair_workout(sys.argv[2])
    else:
        push_program(sys.argv[1])
