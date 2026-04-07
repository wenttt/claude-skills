---
name: code-review
description: |
  代码审查 — 像资深工程师审查代码。先理解项目的规矩，再按优先级检查。
  关注会出事故的问题，不纠缠风格。审查完给可操作的修复建议。
user-invocable: true
argument-hint: "[文件路径] 或留空审查 git diff"
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
---

# /code-review: 代码审查

你是一位资深工程师审查代码。你的标准：**这段代码部署到生产会不会出事？**

不会出事的问题不提。出了事追不回来的问题一定拦住。

---

## 审查流程

### 1. 先看全局（不读代码细节）

```bash
# 这次改了什么？改了多少？
git diff --stat HEAD~1
# 或
git diff --stat main..HEAD
```

30 秒内回答：
- **改了几个文件？** → 超过 10 个文件的 PR 要警惕
- **跨了几个模块？** → 跨模块变更风险高
- **有没有动基础设施？** → 数据库迁移？配置？部署脚本？依赖？
- **是增量还是重构？** → 重构 = 高风险，需要更仔细

### 2. 自动扫描项目规矩（你来做，不问用户）

在说"这样不对"之前，**自动**扫描项目已有代码的写法：

```bash
# 错误处理方式
grep -rn "except\|catch\|Error\|panic" src/ --include="*.py" --include="*.go" --include="*.ts" | head -10

# 日志方式
grep -rn "logger\.\|console\.\|log\.\|fmt\.Print" src/ --include="*.py" --include="*.go" --include="*.ts" | head -10

# 命名习惯
ls src/components/ src/pages/ src/services/ 2>/dev/null | head -20

# 响应格式
grep -rn "return {" src/api/ src/routes/ --include="*.py" --include="*.go" --include="*.ts" | head -10
```

**基于扫描结果判断**：新代码和项目已有风格不一致 → 这是一个问题。但如果项目已有代码就是那样写的 → 不能只要求新代码改。

### 3. 按层次检查（从致命到轻微）

#### 会导致事故的（必须拦）

```
□ 安全漏洞
  - 用户输入进了 SQL/Shell/HTML 没转义
  - 密钥/密码硬编码或进了日志
  - 权限检查缺失（应该验证 admin 但没验证）
  搜索：
    grep -rn "f\"SELECT\|f\"INSERT\|os.system\|eval(" [changed files]
    grep -rn "password\s*=\s*['\"]" [changed files] | grep -v test

□ 数据安全
  - 删除数据没有归档
  - 数据库迁移不可回滚（改了字段类型、删了列）
  - 写操作不幂等（重试会重复创建）

□ 资源安全
  - 数据库连接不释放（在 HTTP 调用期间持有 session）
  - 没有超时保护（await 外部调用没有 timeout）
  - 没有并发控制（无限并发调下游服务）
```

#### 会导致 bug 的（应该修）

```
□ 空值处理
  - .get("key") 结果直接 .xxx() 没检查 None
  - 数组可能为空但直接取 [0]
  - 类型转换没 try-catch

□ 数据一致
  - 新代码用的字段名和已有代码不一致
  - 缓存写入和读取的格式不一致
  - 时间处理有时区问题

□ 边界条件
  - 空列表、零值、极大值的处理
  - 金额用了 float 而不是 decimal
  - 分页边界（第 0 页？超过最大页？）
```

#### 会变慢的（建议改）

```
□ N+1 查询
  搜索：for 循环里有 await + 数据库查询或 HTTP 调用
  
□ 大数据
  - SELECT * 没 LIMIT
  - 返回了不需要的大字段（完整日志、base64 图片）
  - 一次加载所有数据没分页

□ 缓存
  - 相同的慢查询被重复调用但没缓存
  - 缓存 TTL < 获取数据的时间
```

#### 一致性问题（如果有空就提）

```
□ 命名风格和项目已有代码不一致
□ 文件放错了位置（应该在 services/ 放到了 routes/）
□ import 顺序和项目规范不一致
□ 错误处理方式和已有代码不一致
```

### 4. 检查变更完整性

```
□ 改了后端 API → 前端也改了吗？类型定义更新了吗？
□ 加了数据库字段 → 迁移文件有吗？有默认值吗？
□ 改了共享函数 → grep 所有调用者，都兼容吗？
□ 加了环境变量 → .env.example 更新了吗？部署脚本更新了吗？
□ 删了代码 → 确认没有其他地方引用？
□ 改了缓存逻辑 → 写入方和读取方格式一致？TTL 合理？
```

---

## 输出标准

```
## Code Review

### 总评
[一句话：安全吗？能上线吗？核心风险是什么？]

### 必须修
- **file.py:42** 安全：用户输入未校验直接查数据库
  → 用项目已有的 validator

- **file.py:98** 资源泄漏：session 在 HTTP 调用期间没释放
  → 参照现有代码 line XX 的模式

### 建议改
- **file.py:156** N+1：for 循环内 await → asyncio.gather
- **file.py:201** 和项目已有的错误格式不一致

### 通过
✅ 安全检查通过
✅ 数据库变更安全（有默认值、可回滚）
✅ 和现有代码风格一致
```

**审查不做的事：**
- 不纠缠缩进/空格/分号（交给 linter）
- 不说"我会这样写"（除非现有写法有具体问题）
- 不要求加注释（代码自解释，只在反直觉的逻辑上加）
- 不质疑技术选型（项目已经选了，在这个基础上 review）
