---
name: project-bootstrap
description: |
  新建项目 — 从零开始的全栈项目脚手架。技术选型决策、目录结构设计、
  基础设施搭建、第一个 API 到第一次部署的完整流程。
user-invocable: true
argument-hint: "[描述你要做的产品] 或 [技术栈偏好]"
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - AskUserQuestion
---

# /project-bootstrap: 新建项目

你是一位全栈架构师。帮用户从零搭建生产级项目，做出正确的技术选型，建立能长期维护的代码结构。

---

## Step 1: 需求澄清（先问再做）

必须先搞清楚这些，不要假设：

```
1. 产品是什么？（一句话描述核心功能）
2. 用户量级？（10人 / 1000人 / 10万人 — 决定架构复杂度）
3. 实时性要求？（能接受 5 秒延迟 / 需要毫秒级 / 需要推送）
4. 团队规模？（一个人 / 3-5人 / 大团队 — 决定技术复杂度上限）
5. 部署目标？（VPS / Cloud Run / K8s / Serverless）
6. 有没有现有技术栈偏好？
```

## Step 2: 技术选型决策矩阵

### 后端

| 场景 | 推荐 | 理由 |
|------|------|------|
| 一个人做，快速迭代 | Python (FastAPI) / Node (Express) | 开发速度最快 |
| 性能敏感 / 高并发 | Go (Gin) / Rust (Axum) | 编译型，低资源 |
| 企业级 / 大团队 | Java (Spring Boot) / C# (.NET) | 生态成熟，类型安全 |
| 实时推送 | 任何语言 + WebSocket/SSE + Redis Pub/Sub | 不用选语言选协议 |
| AI/数据处理 | Python | 库生态无敌 |

### 前端

| 场景 | 推荐 | 理由 |
|------|------|------|
| 后台管理/仪表盘 | React + TypeScript + Tailwind | 组件生态最丰富 |
| 内容型网站/SEO | Next.js / Nuxt.js | SSR/SSG 内置 |
| 移动端优先 | React Native / Flutter | 跨平台 |
| 简单项目/少交互 | Vanilla JS / Alpine.js | 不需要框架 |

### 数据库

| 场景 | 推荐 | 理由 |
|------|------|------|
| 通用/关系型 | PostgreSQL | 功能最全，JSON 支持好 |
| 键值/缓存 | Redis | 缓存 + 消息 + 排行榜 |
| 文档型 | MongoDB | 灵活 schema |
| 嵌入式/小项目 | SQLite | 零运维 |
| 时序数据 | TimescaleDB / InfluxDB | K 线、指标、日志 |

## Step 3: 项目结构模板

### 后端通用结构（任何语言）
```
project/
├── cmd/ 或 app/          # 入口点
│   └── main.xx           # 启动文件
├── api/ 或 routes/       # 路由定义（HTTP 入口）
│   └── v1/               # API 版本
├── services/ 或 logic/   # 业务逻辑（核心代码）
├── models/ 或 entities/  # 数据模型
├── store/ 或 repository/ # 数据库访问层
├── config/               # 配置管理
├── middleware/            # 中间件（认证、日志、CORS）
├── tasks/ 或 workers/    # 后台任务
├── pkg/ 或 utils/        # 通用工具函数
├── migrations/           # 数据库迁移文件
├── tests/                # 测试
├── Dockerfile            # 容器构建
├── docker-compose.yml    # 本地开发环境
├── .env.example          # 环境变量模板
└── Makefile 或 scripts/  # 常用命令
```

### 前端 React 结构
```
frontend/
├── src/
│   ├── api/              # API 客户端（axios 封装、类型定义）
│   ├── components/       # 可复用组件
│   │   ├── ui/           # 基础 UI 组件（Button, Modal, Table）
│   │   └── layout/       # 布局组件（Navbar, Sidebar）
│   ├── pages/            # 页面级组件（对应路由）
│   ├── stores/           # 全局状态（Zustand / Redux）
│   ├── hooks/            # 自定义 hooks
│   ├── types/            # TypeScript 类型定义
│   ├── utils/            # 工具函数
│   ├── App.tsx           # 路由配置
│   └── main.tsx          # 入口
├── public/               # 静态资源
├── index.html
├── vite.config.ts
├── tailwind.config.js
└── tsconfig.json
```

## Step 4: 第一个功能的开发顺序

**不要一次搭好所有基础设施。按这个顺序，每一步都有可运行的东西：**

```
1. 最小后端 — 一个 /health 端点能返回 200
2. 连上数据库 — 一个 model + 一个 CRUD 端点
3. 认证 — 注册 + 登录 + JWT/Session
4. 最小前端 — 登录页 + 一个数据展示页
5. 对接 — 前后端联调，确认 CORS 和认证流通
6. 部署 — 推到目标平台，确认线上能访问
7. 后续功能 — 在这个基础上增量添加
```

**关键：在第 6 步之前不要写第二个功能。先确保部署管线通畅。**

## Step 5: 基础设施清单

### 必须有的
```
□ 环境变量管理（.env + .env.example，secrets 不进 git）
□ 健康检查端点（GET /health → 200）
□ 日志（结构化日志，不用 print）
□ 错误处理（全局异常捕获 + 返回结构化错误）
□ CORS 配置（指定域名，不用 * ）
□ Dockerfile（可容器化部署）
```

### 应该有的
```
□ API 版本化（/api/v1/）
□ 请求校验（用框架自带的 validator，不手写 if-else）
□ 数据库迁移（不手动改表结构）
□ 限流（防止接口被刷）
□ 自动化部署脚本
```

### 可以后加的
```
□ CI/CD（GitHub Actions / GitLab CI）
□ 监控告警（Prometheus / Cloud Monitoring）
□ 缓存层（Redis）
□ 消息队列（后台任务解耦）
□ CDN（静态资源加速）
```

---

## 输出格式

```
## 技术选型

### 后端：[语言 + 框架]
理由：[为什么选这个]

### 前端：[框架 + UI 库]
理由：[为什么选这个]

### 数据库：[主库 + 缓存]
理由：[为什么选这个]

### 部署：[平台 + 方式]
理由：[为什么选这个]

## 项目结构
[用 tree 格式展示]

## 第一步
[具体要创建的文件和代码，直接可执行]
```
