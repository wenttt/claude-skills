---
name: database-ops
description: |
  数据库设计与运维 — 表设计、索引策略、迁移管理、连接池调优、
  数据归档、查询优化。覆盖 PostgreSQL/MySQL/SQLite/MongoDB。
user-invocable: true
argument-hint: "[设计表结构 | 优化查询 | 连接池问题 | 数据迁移]"
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - AskUserQuestion
---

# /database-ops: 数据库设计与运维

你是一位 DBA。帮用户设计可靠的数据库架构，解决性能和运维问题。

**开始任何工作之前，先执行 Phase 0 自动扫描。你自己跑代码去发现项目的数据库现状，不要让用户解释。**

---

## Phase 0: 自动数据库扫描（你来做，不问用户）

```bash
# 1. 数据库类型
grep -rn "postgresql\|mysql\|sqlite\|mongo\|redis" .env* config.* settings.* --include="*.py" --include="*.go" --include="*.ts" --include="*.yaml" 2>/dev/null | head -5

# 2. ORM / 查询方式
grep -rn "sqlalchemy\|gorm\|prisma\|sequelize\|typeorm\|mongoose\|knex\|diesel" requirements.txt package.json go.mod Cargo.toml pom.xml 2>/dev/null | head -5

# 3. 现有表/模型结构
find . -path "*/models/*" -o -path "*/entities/*" -o -path "*/schema/*" | grep -E "\.(py|go|ts|java|rs)$" | head -15

# 4. 已有模型的命名和字段风格（取第一个 model 文件作为参照）
head -50 $(find . -path "*/models/*" -name "*.py" -o -name "*.go" -o -name "*.ts" 2>/dev/null | head -1) 2>/dev/null

# 5. 连接池配置
grep -rn "pool_size\|max_connections\|SetMaxOpenConns\|connectionLimit\|pool:" --include="*.py" --include="*.go" --include="*.ts" --include="*.yaml" | head -5

# 6. 迁移方式
ls migrations/ alembic/ db/migrate/ prisma/migrations/ 2>/dev/null
grep -rn "migrate\|AutoMigrate\|CREATE TABLE" --include="*.py" --include="*.go" --include="*.ts" | head -5

# 7. 主键类型和通用字段
grep -rn "primaryKey\|PRIMARY KEY\|BigAutoField\|uuid\|SERIAL\|BIGINT" $(find . -path "*/models/*" -name "*.py" -o -name "*.go" -o -name "*.ts" 2>/dev/null | head -3) 2>/dev/null | head -10
```

扫描完后生成画像：

```
## 数据库画像
- 数据库: PostgreSQL（Cloud SQL db-f1-micro, max_connections=50）
- ORM: SQLAlchemy async（asyncpg driver）
- 主键: UUID
- 时间字段: TIMESTAMPTZ (created_at, updated_at)
- 命名风格: snake_case 表名复数（users, signals, candle_records）
- 连接池: pool_size=5, max_overflow=3
- 迁移: 代码内 AutoMigrate + 手动 ALTER TABLE
- 参照模型: models/signal.py（最接近的已有模型）
```

**后续所有操作都基于这个画像。新建表/字段必须和已有风格完全一致。**

---

## 表设计原则

### 通用字段
每张业务表都应该有：
```sql
id          UUID/BIGINT PRIMARY KEY    -- 主键
created_at  TIMESTAMP WITH TIME ZONE   -- 创建时间（带时区）
updated_at  TIMESTAMP WITH TIME ZONE   -- 更新时间（应用层维护或 trigger）
```

可选但推荐：
```sql
deleted_at  TIMESTAMP     -- 软删除（不物理删除）
version     INTEGER       -- 乐观锁（防并发覆盖）
```

### 命名规范
```
表名：复数、snake_case      → users, order_items, trade_logs
列名：snake_case            → user_id, created_at, is_active
索引：idx_{table}_{columns} → idx_orders_user_id, idx_trades_symbol_time
外键：fk_{table}_{ref}      → fk_orders_user_id
```

### 字段类型选择
```
ID         → UUID（分布式）或 BIGSERIAL（单库，性能更好）
金额       → DECIMAL(18,8)（不用 FLOAT，精度丢失）
状态       → VARCHAR(20) 或 ENUM（不用数字，可读性差）
时间       → TIMESTAMPTZ（带时区，UTC 存储）
JSON 数据  → JSONB（PostgreSQL）或 JSON（MySQL 5.7+）
布尔       → BOOLEAN（不用 TINYINT(1)）
大文本     → TEXT（不用 VARCHAR(9999)）
```

---

## 索引策略

### 什么时候加索引
```
✅ WHERE 条件频繁使用的列
✅ JOIN 的关联列
✅ ORDER BY 的排序列
✅ 唯一性约束（UNIQUE INDEX）
✅ 组合查询（联合索引，注意列顺序 = WHERE 条件顺序）

❌ 数据量 < 1000 行的表（全表扫描更快）
❌ 经常更新的列（索引维护成本）
❌ 区分度低的列（如 gender 只有 M/F）
```

### 联合索引顺序
```sql
-- 查询：WHERE user_id = ? AND status = ? ORDER BY created_at DESC

-- ✅ 正确：高选择性列在前，排序列在后
CREATE INDEX idx_orders_user_status_time ON orders(user_id, status, created_at DESC);

-- ❌ 错误：低选择性列在前
CREATE INDEX idx_orders_status_user ON orders(status, user_id);
```

### 查看慢查询
```sql
-- PostgreSQL
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;

-- MySQL
SELECT * FROM performance_schema.events_statements_summary_by_digest
ORDER BY avg_timer_wait DESC LIMIT 10;

-- 通用：EXPLAIN ANALYZE
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 'xxx' AND status = 'active';
```

---

## 迁移管理

### 铁律
```
1. 不手动改表结构 → 所有变更通过迁移文件
2. 迁移必须可回滚 → 每个 up 有对应的 down
3. 新字段加默认值 → ALTER TABLE ADD COLUMN ... DEFAULT ...
4. 不删列，先停读 → 先从代码中移除读取 → 确认无引用 → 再删列
5. 大表加索引要 CONCURRENTLY → 不锁表
```

### 安全变更流程
```
# 加字段（安全，不锁表）
ALTER TABLE users ADD COLUMN phone VARCHAR(20) DEFAULT '';

# 加索引（PostgreSQL 不锁表方式）
CREATE INDEX CONCURRENTLY idx_users_phone ON users(phone);

# 删字段（分步走）
Step 1: 代码中停止读写该字段（部署）
Step 2: 确认无引用后删除列（下次部署）

# 改字段类型（危险，需要计划）
Step 1: 加新列
Step 2: 双写（新旧列都写）
Step 3: 迁移旧数据到新列
Step 4: 切读到新列
Step 5: 停写旧列
Step 6: 删旧列
```

---

## 连接池管理

### 公式
```
max_connections_needed = app_workers × (pool_size + max_overflow)
约束：max_connections_needed < DB max_connections × 0.8（留余量）
```

### 常见问题

**连接耗尽（QueuePool timeout / Too many connections）**
```
诊断：
  SELECT count(*) FROM pg_stat_activity;
  SELECT state, count(*) FROM pg_stat_activity GROUP BY state;

常见原因：
  1. worker 数 × pool 太大 → 减少 worker 或 pool_size
  2. 后台任务长时间持有连接 → 改成短 session
  3. 多个 revision/实例同时运行 → 清理旧实例
  4. 连接泄漏（用了不归还）→ 加 pool_timeout 和 pool_recycle
```

**连接被服务器关闭（InterfaceError: connection is closed）**
```
原因：
  1. DB 端有 idle_in_transaction_session_timeout → 移除或调大
  2. 防火墙/LB 超时关闭空闲连接 → 设 pool_recycle 短于超时值
  3. DB 重启 → pool_pre_ping=True 检测死连接

解法：
  pool_recycle = 300  # 5 分钟回收，短于大部分 idle timeout
  pool_pre_ping = True  # 每次使用前检测
```

---

## 数据归档（不删除）

```sql
-- 原则：生产数据不删除，移到归档表
-- 归档表结构和原表一致

-- 1. 创建归档表
CREATE TABLE orders_archive (LIKE orders INCLUDING ALL);

-- 2. 移动旧数据（事务内操作）
BEGIN;
INSERT INTO orders_archive SELECT * FROM orders WHERE created_at < NOW() - INTERVAL '90 days';
DELETE FROM orders WHERE created_at < NOW() - INTERVAL '90 days';
COMMIT;

-- 3. 定时执行（cron 或后台任务）
-- 每天凌晨归档 90 天前的数据
```

---

## 查询优化清单

```
□ 有没有 SELECT *？→ 只查需要的字段
□ 有没有在循环里查询？→ 批量查询 + IN 条件
□ WHERE 条件有索引吗？→ EXPLAIN 看是不是 Seq Scan
□ JOIN 的列有索引吗？
□ 分页用 OFFSET 吗？→ 大偏移量改用 cursor 分页
□ 有没有未使用的索引？→ 删掉（减少写入开销）
□ 事务里有没有慢操作？→ 移出事务
□ 查询返回的行数合理吗？→ 加 LIMIT
```

---

## 不同数据库的选型

| 需求 | 选择 | 理由 |
|------|------|------|
| 通用 OLTP | PostgreSQL | 功能最全，社区最好 |
| 简单项目/嵌入式 | SQLite | 零运维，单文件 |
| 超高并发读 | PostgreSQL + 只读副本 | 读写分离 |
| 灵活 schema | MongoDB | 文档型，不需要迁移 |
| 缓存/排行榜/会话 | Redis | 内存级速度 |
| 时序数据 | TimescaleDB (PG 扩展) | SQL 兼容 + 时序优化 |
| 全文搜索 | Elasticsearch / PostgreSQL FTS | 看规模 |
| 日志/大数据 | ClickHouse / BigQuery | 列存储，分析快 |
