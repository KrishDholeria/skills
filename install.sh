#!/usr/bin/env bash
# Symlink every skill dir (contains SKILL.md) into ~/.claude/skills/.
# Backs up anything it supersedes into legacy/. Safe to re-run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
COMMANDS_DIR="$HOME/.claude/commands"
LEGACY_DIR="$REPO_DIR/legacy"
STAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$SKILLS_DIR" "$LEGACY_DIR/commands" "$LEGACY_DIR/skills"

# Superseded slash commands: a skill and a command with the same name conflict.
SUPERSEDED_COMMANDS=(connect-db view-tickets review-pr post-review-comments)
for cmd in "${SUPERSEDED_COMMANDS[@]}"; do
  src="$COMMANDS_DIR/$cmd.md"
  if [[ -f "$src" ]]; then
    mv "$src" "$LEGACY_DIR/commands/$cmd.md.$STAMP"
    echo "backed up command: $cmd.md -> legacy/commands/$cmd.md.$STAMP"
  fi
done

linked=0
for dir in "$REPO_DIR"/*/; do
  name="$(basename "$dir")"
  [[ -f "$dir/SKILL.md" ]] || continue
  target="$SKILLS_DIR/$name"

  if [[ -L "$target" ]]; then
    : # existing symlink — re-point below
  elif [[ -d "$target" ]]; then
    mv "$target" "$LEGACY_DIR/skills/$name.$STAMP"
    echo "backed up skill dir: $name -> legacy/skills/$name.$STAMP"
  fi

  ln -sfn "${dir%/}" "$target"
  echo "linked: ~/.claude/skills/$name -> ${dir%/}"
  linked=$((linked + 1))
done

echo "done: $linked skill(s) linked."
