# Claude Code Skills

Personal collection of custom skills for [Claude Code](https://claude.ai/claude-code).

## Skills

### Thinking 思维工具
| Skill | Description |
|-------|-------------|
| [polanyi](thinking/polanyi/) | 隐性知识思维教练 — 帮你把"说不出来但知道"的东西挖掘、外化、整合 |

### Engineering 全栈开发
| Skill | Description |
|-------|-------------|
| [senior-engineer](engineering/senior-engineer/) | 资深工程师思维 — 代码质量标准、架构判断力、审查检查点 |
| [project-takeover](engineering/project-takeover/) | 接手/二开项目 — 5 分钟摸清陌生代码库的系统方法 |
| [project-bootstrap](engineering/project-bootstrap/) | 新建项目 — 技术选型、项目结构、从零到部署的完整流程 |
| [frontend-dev](engineering/frontend-dev/) | 前端开发 — 数据加载三层架构、状态管理、组件设计、性能优化 |
| [backend-dev](engineering/backend-dev/) | 后端开发 — API 设计、认证、数据库交互、后台任务、错误处理 |
| [database-ops](engineering/database-ops/) | 数据库 — 表设计、索引策略、迁移管理、连接池调优、归档 |
| [system-design](engineering/system-design/) | 系统架构 — 缓存/解耦/降级/背压的通用设计模式 |
| [deploy-safety](engineering/deploy-safety/) | 安全部署 — 部署前/中/后检查、健康检查、回滚策略 |
| [debug-method](engineering/debug-method/) | 系统排错 — 四步定位法、常见 bug 模式速查 |

## Install

```bash
./install.sh                           # Install all
./install.sh engineering/frontend-dev   # Install one
```

## Usage

```bash
# 接手一个陌生项目
/project-takeover /path/to/project

# 从零开始新项目
/project-bootstrap 我要做一个量化交易监控平台

# 写前端功能
/frontend-dev 做一个带筛选和分页的交易记录表

# 写后端 API
/backend-dev 设计一个用户认证系统

# 数据库设计
/database-ops 设计交易记录表，需要按时间和币种查询

# 检查代码质量
/senior-engineer 审查这个 PR

# 排查线上问题
/debug-method 页面打开后所有请求都显示"已取消"
```

## License

MIT
