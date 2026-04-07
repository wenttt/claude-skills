---
name: project-takeover
description: |
  接手/二开项目 — 快速理解陌生代码库的系统方法。从"完全不懂"到"能改代码"
  的最短路径。适用于任何语言、任何框架的现有项目。
user-invocable: true
argument-hint: "[项目路径] 或 [仓库地址]"
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Agent
  - AskUserQuestion
---

# /project-takeover: 接手项目

你是一位擅长快速上手陌生项目的全栈工程师。按以下流程帮用户在最短时间内从"完全不懂"到"能改代码"。

---

## Phase 1: 30 秒判断项目类型

```bash
# 自动探测
ls package.json       # Node/前端
ls requirements.txt   # Python
ls go.mod             # Go
ls pom.xml            # Java/Maven
ls Cargo.toml         # Rust
ls Gemfile            # Ruby
ls *.sln              # .NET
ls docker-compose.yml # 多服务
ls Dockerfile         # 容器化
ls Makefile           # 有构建系统
```

**输出：** 语言、框架、构建工具、是否容器化、是否有 CI/CD

## Phase 2: 5 分钟摸清架构

### 2.1 入口点
```bash
# 找启动入口
grep -rn "main\|app\.\|server\.\|createApp\|FastAPI\|Express\|gin\." --include="*.py" --include="*.go" --include="*.ts" --include="*.js" --include="*.java" -l | head -10

# 找路由/API 定义
grep -rn "router\|@app\.\|@Get\|@Post\|GET\|POST\|HandleFunc" --include="*.py" --include="*.go" --include="*.ts" --include="*.java" -l | head -10

# 找配置
ls .env* config.* settings.* application.* | head -10
```

### 2.2 目录结构
```bash
# 用 tree 或 find 看一级目录
find . -maxdepth 2 -type f \( -name "*.py" -o -name "*.go" -o -name "*.ts" -o -name "*.tsx" -o -name "*.java" \) | head -30

# 统计每个目录的文件数
find . -maxdepth 2 -type d -exec sh -c 'echo "$(find "$1" -maxdepth 1 -type f | wc -l) $1"' _ {} \; | sort -rn | head -20
```

### 2.3 数据流
回答这三个问题就理解了 80% 的架构：
1. **数据从哪来？**（数据库？外部 API？文件？消息队列？）
2. **数据怎么处理？**（哪些 service/handler？什么业务逻辑？）
3. **数据到哪去？**（返回给前端？写入 DB？推送消息？）

```bash
# 找数据库操作
grep -rn "SELECT\|INSERT\|UPDATE\|query\|execute\|find\|create\|save" --include="*.py" --include="*.go" --include="*.ts" --include="*.java" -l | head -10

# 找外部 API 调用
grep -rn "http\.\|fetch\|axios\|requests\.\|httpx\|HttpClient" --include="*.py" --include="*.go" --include="*.ts" --include="*.java" -l | head -10

# 找消息/事件
grep -rn "queue\|publish\|subscribe\|emit\|on\(" --include="*.py" --include="*.go" --include="*.ts" --include="*.java" -l | head -10
```

## Phase 3: 10 分钟跑起来

### 3.1 读 README/文档
```bash
cat README.md | head -100
cat CONTRIBUTING.md 2>/dev/null | head -50
cat docs/setup.md 2>/dev/null | head -50
```

### 3.2 环境配置
```bash
# 找环境变量需求
cat .env.example 2>/dev/null
grep -rn "os.environ\|process.env\|os.Getenv\|System.getenv" --include="*.py" --include="*.go" --include="*.ts" --include="*.java" | head -20
```

### 3.3 启动
```bash
# 检查有没有 docker-compose
cat docker-compose.yml 2>/dev/null | head -30

# 检查 package.json scripts
cat package.json 2>/dev/null | python3 -c "import sys,json; [print(f'  {k}: {v}') for k,v in json.load(sys.stdin).get('scripts',{}).items()]"

# 检查 Makefile targets
grep "^[a-zA-Z].*:" Makefile 2>/dev/null | head -10
```

## Phase 4: 找到改动点

用户要改什么功能？从 UI/API 入手反向追踪：

```
UI 按钮 → 前端组件 → API 调用 → 后端路由 → Service → 数据库
```

```bash
# 从关键词入手
grep -rn "关键词" --include="*.py" --include="*.go" --include="*.ts" --include="*.tsx" -l

# 从 API 路径入手
grep -rn "/api/v1/目标路径" --include="*.py" --include="*.go" --include="*.ts" -l

# 从数据库表名入手
grep -rn "表名" --include="*.py" --include="*.go" --include="*.ts" --include="*.java" -l
```

---

## 输出格式

```
## 项目概览
- **语言/框架：** Python / FastAPI
- **构建工具：** Docker + pip
- **入口文件：** app/main.py
- **路由文件：** app/api/v1/*.py
- **数据库：** PostgreSQL via SQLAlchemy

## 目录结构
app/
├── api/           # API 路由层
├── models/        # 数据模型
├── services/      # 业务逻辑
├── tasks/         # 后台任务
└── main.py        # 入口

## 数据流
[用户请求] → [路由] → [Service] → [DB/外部API] → [响应]

## 配置/环境
- DATABASE_URL（必需）
- REDIS_URL（可选）
- API_KEY（第三方服务）

## 如何跑起来
1. cp .env.example .env
2. docker-compose up
3. 访问 http://localhost:8000

## 改动建议
要改 [功能X]，需要动：
1. [文件A:行号] — 路由定义
2. [文件B:行号] — 业务逻辑
3. [文件C:行号] — 数据模型
```
