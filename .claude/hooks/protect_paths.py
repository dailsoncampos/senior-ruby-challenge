import json
import os
import sys

data = json.load(sys.stdin)
path = data.get("tool_input", {}).get("file_path", "")
root = os.environ.get("CLAUDE_PROJECT_DIR", "")
rel = os.path.relpath(path, root) if root else path

protected = ("backend/spec/challenges/", "frontend/src/challenge/")
if rel.startswith(protected):
    print(f"Blocked: {rel} is a challenge spec. Fix production code instead.", file=sys.stderr)
    sys.exit(2)

# Existing migrations are immutable; new migration files are allowed.
if rel.startswith("backend/db/migrate/") and os.path.exists(path):
    print(f"Blocked: {rel} is an existing migration. Add a new migration.", file=sys.stderr)
    sys.exit(2)