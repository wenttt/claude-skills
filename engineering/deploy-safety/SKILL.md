---
name: deploy-safety
description: |
  安全部署 skill — 任何平台（Cloud Run/K8s/VPS/Vercel/Docker）通用的
  部署流程、验证步骤、回滚策略。确保每次部署不搞坏现有功能。
user-invocable: true
argument-hint: "[pre-deploy 检查 | post-deploy 验证 | 写部署脚本 | 回滚方案]"
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - AskUserQuestion
---

# /deploy-safety: 安全部署

你是一位 SRE 工程师。确保每次部署安全、可验证、可回滚。

---

## 部署三阶段

### Phase 1: Pre-deploy（部署前）

```
□ 代码变更已 review
□ 旧实例已清理（防止资源争抢：DB 连接、端口、锁）
□ 部署脚本包含所有关键参数（不依赖"上次手动改的值"）
□ 明确回滚方案（回滚到哪个版本？怎么回？）
□ 数据库迁移兼容（新旧代码能同时跑？字段有默认值？）
```

### Phase 2: Deploy（部署中）

```
□ 滚动更新期间新旧版本共存 → 确认不冲突
  - DB 连接数：两个版本 × pool_size 之和 < max_connections
  - API 兼容：新版本的 API 响应格式不破坏旧版前端
□ 等待完全启动后再测试（warmup 时间因语言而异）
  - Go/Rust: 5-10s
  - Python/Node: 15-30s
  - Java/JVM: 30-90s
□ 不在部署期间做其他变更
```

### Phase 3: Post-deploy（部署后）

```
□ 健康检查：HTTP 200 + 响应时间正常
□ 功能验证：至少测试 3 个核心端点
  - 认证：登录/注册能用
  - 主功能：核心业务接口返回数据
  - 后台任务：定时任务在跑
□ 日志检查：搜索 ERROR/Exception/Timeout（最近 2 分钟）
□ 清理：删除旧版本实例
□ 通知：告诉团队部署完成
```

---

## 部署脚本模板

```bash
#!/bin/bash
set -e

# ---- 配置（所有参数固化在这里）----
SERVICE="my-service"
IMAGE="registry/my-service:$TAG"
# 关键：这些值不能漏，每次部署从这里读
MEMORY="2Gi"
CPU="1"
MIN_INSTANCES="1"
MAX_INSTANCES="3"

# ---- Phase 1: 清理 ----
echo "Step 1: Cleaning old instances..."
# [平台特定的清理命令]

# ---- Phase 2: 部署 ----
echo "Step 2: Deploying $IMAGE..."
# [平台特定的部署命令，包含所有参数]

# ---- Phase 3: 验证 ----
echo "Step 3: Waiting for warmup..."
sleep ${WARMUP_SECONDS:-60}

echo "Step 4: Smoke test..."
PASS=true
for endpoint in "/health" "/api/v1/status"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 20 "$SERVICE_URL$endpoint")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "401" ]; then
    echo "  ✓ $endpoint ($STATUS)"
  else
    echo "  ✗ $endpoint ($STATUS)"
    PASS=false
  fi
done

# ---- Phase 4: 清理旧版本 ----
echo "Step 5: Cleaning previous version..."
# [清理旧实例/revision]

if [ "$PASS" = true ]; then
  echo "=== Deploy successful ==="
else
  echo "=== WARNING: Some checks failed ==="
  exit 1
fi
```

---

## 健康检查设计

### 必须满足的条件
```
1. 健康检查穿透到业务进程（不能在网关/反代层短路返回 200）
2. 多进程容器：任一进程死亡 → 容器退出（supervisor 模式）
3. 健康检查包含关键依赖（能连上 DB？能连上缓存？）
4. 启动探测宽松（允许 2-5 分钟），存活探测严格（90s 无响应 → 重启）
```

### 反模式
```
❌ nginx 写死 return 200（业务进程死了也返回健康）
❌ 只检查 HTTP 端口（进程在但逻辑死锁）
❌ 健康检查依赖外部服务（外部挂了 ≠ 我挂了）
❌ 没有存活探测（僵死进程永远不重启）
```

---

## 回滚策略

### 快速回滚（< 2 分钟）
```
保留上一个版本的部署制品（镜像/包），出问题直接切回：
  - 容器平台：回滚到上一个 revision/deployment
  - 传统部署：保留上一个 release 目录，nginx 切 symlink
  - Serverless：保留上一个 function version
```

### 数据库回滚
```
原则：数据库迁移必须向前兼容
  - 加字段：设默认值 → 新旧代码都能跑
  - 改字段名：先加新名 → 两个名都写 → 迁移完删旧名
  - 删字段：先停止读取 → 确认无引用 → 再删
  - 不删数据：归档到 _archive 表
```

---

## 常见事故模式

| 事故 | 根因 | 预防 |
|------|------|------|
| 部署后登录挂 | 新旧版本同时抢 DB 连接 | 先清旧版本再部署 |
| 部署后页面空白 | 前端缓存了旧 JS，调新 API 格式不对 | 前端加 hash 文件名 + no-cache |
| 部署后数据丢失 | 新代码写了不兼容的数据格式 | 先部署读兼容的代码 |
| 回滚后更坏 | 回滚代码依赖了已迁移的 DB | 数据库迁移和代码变更分开部署 |
| 部署成功但功能异常 | 没有 smoke test，只看了 /health 200 | 测核心业务端点 |
