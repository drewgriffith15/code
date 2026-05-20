---
name: theo-push
description: Push a locally edited THEO lesson draft to Notion. Accepts a markdown file path from Construct/wiki/theology/lessons/, creates a private page under the THEO hub, and returns the Notion URL. Use when Drew is done editing a draft locally and wants to publish it to Notion.
model: claude-sonnet-4-6
---

# THEO Notion Push

Pushes a finished local draft to Notion. The draft must be a markdown file from:
`C:\Users\wgriffith2\Dropbox (Liberty University)\Construct\wiki\theology\lessons\`

The page is created as a child of the THEO hub: https://www.notion.so/THEO-35bee045d5ec80da97b8d003434ffb43

## Step 1 — Collect file path

If the user provided a file path in the command args, use it. If not, ask:

> Which draft file do you want to push to Notion? Provide the full path.
>
> Drafts are in: `C:\Users\wgriffith2\Dropbox (Liberty University)\Construct\wiki\theology\lessons\`

Wait for the path before continuing.

## Step 2 — Confirm and run

Show the user what is about to run:

> Ready to push to Notion:
> `<file_path>`
>
> This will create a new private page under your THEO hub. Proceed?

Wait for confirmation. Then run:

```bash
python "C:/Users/wgriffith2/Dropbox (Liberty University)/Code/theo_notion_push.py" --file "<file_path>"
```

## Step 3 — Report result

After the run completes, report:

```
/theo-push complete

File:   <file_path>
Notion: <notion_url>
```

The Notion URL is printed as `Notion page created: https://...`

If the run fails, report the full error output and stop.
