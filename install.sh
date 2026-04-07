#!/bin/bash
# Install Claude Code skills by symlinking to ~/.claude/skills/ and ~/.claude/commands/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
COMMANDS_DIR="$HOME/.claude/commands"

mkdir -p "$SKILLS_DIR" "$COMMANDS_DIR"

install_skill() {
    local skill_path="$1"
    local skill_name="$(basename "$skill_path")"
    local source="$SCRIPT_DIR/$skill_path"

    if [ ! -f "$source/SKILL.md" ]; then
        echo "  SKIP $skill_path (no SKILL.md)"
        return
    fi

    # Symlink skill directory
    if [ -L "$SKILLS_DIR/$skill_name" ]; then
        rm "$SKILLS_DIR/$skill_name"
    fi
    ln -sf "$source" "$SKILLS_DIR/$skill_name"
    echo "  LINK $skill_name -> $source"

    # Create command shortcut if it doesn't exist
    local cmd_file="$COMMANDS_DIR/$skill_name.md"
    if [ ! -f "$cmd_file" ] || [ -L "$cmd_file" ]; then
        # Extract description from SKILL.md frontmatter
        local desc=$(sed -n '/^description:/,/^[a-z]/{ /^description:/{ s/^description: *//; s/|//; p; }; /^  /p; }' "$source/SKILL.md" | head -1 | xargs)
        [ -z "$desc" ] && desc="$skill_name skill"

        cat > "$cmd_file" << EOF
---
name: $skill_name
description: $desc
user-invocable: true
---

读取并执行 \`~/.claude/skills/$skill_name/SKILL.md\` 中的完整 skill 定义。
EOF
        echo "  CMD  $skill_name.md"
    fi
}

if [ -n "$1" ]; then
    # Install specific skill
    echo "Installing $1..."
    install_skill "$1"
else
    # Install all skills
    echo "Installing all skills..."
    for category_dir in "$SCRIPT_DIR"/*/; do
        category="$(basename "$category_dir")"
        [ "$category" = "commands" ] && continue
        [ ! -d "$category_dir" ] && continue
        for skill_dir in "$category_dir"/*/; do
            [ ! -d "$skill_dir" ] && continue
            skill_name="$(basename "$skill_dir")"
            install_skill "$category/$skill_name"
        done
    done
fi

echo ""
echo "Done. Restart Claude Code to pick up new skills."
