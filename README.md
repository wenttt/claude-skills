# Claude Code Skills

Personal collection of custom skills for [Claude Code](https://claude.ai/claude-code).

## Skills

| Skill | Category | Description |
|-------|----------|-------------|
| [polanyi](thinking/polanyi/) | thinking | 隐性知识思维教练 — 基于 Michael Polanyi 的认识论框架，通过引导式提问帮你把"说不出来但知道"的东西挖掘、外化、整合 |

## Categories

- **thinking** — 思维工具：帮助思考、分析、决策
- **creation** — 创作工具：帮助内容创作、写作
- **decision** — 决策工具：帮助做判断、做选择
- **workflow** — 工作流工具：自动化、流程优化

## Install

```bash
# Install all skills
./install.sh

# Install a specific skill
./install.sh thinking/polanyi
```

## Usage

After installation, use in Claude Code:

```
/polanyi 我想聊聊为什么我对AI时代的内容创作有一种矛盾感
/polanyi --mode create 关于隐性知识的文章
/polanyi --mode think 要不要做这个项目
```

## Add a new skill

1. Pick or create a category directory
2. Create `{category}/{skill-name}/SKILL.md`
3. Run `./install.sh` to symlink
4. Optionally add a command shortcut in `commands/`

## License

MIT
