#!/bin/bash
set -euo pipefail

# Strict mirror consistency audit for ~/.agents against this repo.
#
# Usage:
#   scripts/check-agent-mirror.sh
#
# Optional overrides:
#   MIRROR_ROOT=/path/to/.agents REPO_ROOT=/path/to/agent-skills scripts/check-agent-mirror.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_REPO_ROOT="$(dirname "$SCRIPT_DIR")"

REPO_ROOT="${REPO_ROOT:-$DEFAULT_REPO_ROOT}"
MIRROR_ROOT="${MIRROR_ROOT:-$HOME/.agents}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required for mirror audit." >&2
  exit 2
fi

python3 - "$REPO_ROOT" "$MIRROR_ROOT" <<'PY'
import sys
from pathlib import Path

repo_root = Path(sys.argv[1]).resolve()
mirror_root = Path(sys.argv[2]).resolve()

errors = []
outside = []

if not repo_root.exists():
    print(f"ERROR: REPO_ROOT does not exist: {repo_root}", file=sys.stderr)
    sys.exit(2)

if not mirror_root.exists():
    print(f"ERROR: MIRROR_ROOT does not exist: {mirror_root}", file=sys.stderr)
    sys.exit(2)

# Expected top-level symlinks.
root_expected = {
    mirror_root / 'AGENTS.md': repo_root / 'AGENTS.md',
    mirror_root / 'hooks': repo_root / 'hooks',
    mirror_root / 'references': repo_root / 'references',
}

for link, expected in root_expected.items():
    if not link.exists() and not link.is_symlink():
        errors.append((str(link), 'missing', str(expected)))
        continue
    if not link.is_symlink():
        errors.append((str(link), 'not_symlink', str(expected)))
        continue
    resolved = link.resolve(strict=False)
    if resolved != expected:
        errors.append((str(link), 'target_mismatch', f'{resolved} != {expected}'))

# Expected agents/*.md symlinks, excluding README.md.
repo_agents = repo_root / 'agents'
mirror_agents = mirror_root / 'agents'
if not repo_agents.exists():
    errors.append((str(repo_agents), 'missing_dir', 'repo agents directory is required'))
elif not mirror_agents.exists():
    errors.append((str(mirror_agents), 'missing_dir', 'mirror agents directory is required'))
else:
    for src in sorted(repo_agents.glob('*.md')):
        if src.name == 'README.md':
            continue
        dst = mirror_agents / src.name
        if not dst.exists() and not dst.is_symlink():
            errors.append((str(dst), 'missing', str(src)))
            continue
        if not dst.is_symlink():
            errors.append((str(dst), 'not_symlink', str(src)))
            continue
        resolved = dst.resolve(strict=False)
        if resolved != src:
            errors.append((str(dst), 'target_mismatch', f'{resolved} != {src}'))

# Expected skills/<name> symlinks for each repo skill directory.
repo_skills = repo_root / 'skills'
mirror_skills = mirror_root / 'skills'
if not repo_skills.exists():
    errors.append((str(repo_skills), 'missing_dir', 'repo skills directory is required'))
elif not mirror_skills.exists():
    errors.append((str(mirror_skills), 'missing_dir', 'mirror skills directory is required'))
else:
    for src in sorted([p for p in repo_skills.iterdir() if p.is_dir()]):
        dst = mirror_skills / src.name
        if not dst.exists() and not dst.is_symlink():
            errors.append((str(dst), 'missing', str(src)))
            continue
        if not dst.is_symlink():
            errors.append((str(dst), 'not_symlink', str(src)))
            continue
        resolved = dst.resolve(strict=False)
        if resolved != src:
            errors.append((str(dst), 'target_mismatch', f'{resolved} != {src}'))

# Track symlinks that resolve outside repo root.
all_links = [p for p in mirror_root.rglob('*') if p.is_symlink()]
for link in all_links:
    target = link.resolve(strict=False)
    try:
        target.relative_to(repo_root)
    except ValueError:
        outside.append((str(link), str(target)))

print(f'MIRROR_ROOT: {mirror_root}')
print(f'REPO_ROOT: {repo_root}')
print(f'TOTAL_SYMLINKS_SCANNED: {len(all_links)}')
print(f'STRICT_ERRORS: {len(errors)}')
print(f'OUTSIDE_REPO_SYMLINKS: {len(outside)}')

if errors:
    print('\nERRORS:')
    for path, kind, detail in errors:
        print(f'- {kind}: {path} :: {detail}')

if outside:
    print('\nOUTSIDE_REPO_LINKS:')
    for link, target in outside:
        print(f'- {link} -> {target}')

sys.exit(1 if (errors or outside) else 0)
PY
