---
name: debug-method
description: |
  系统性排错方法论 — 不靠猜，靠证据。四步定位法：现象→数据→假设→验证。
  适用于任何语言、任何系统的 bug 排查。拒绝"试试看"式调试。
user-invocable: true
argument-hint: "[描述现象或粘贴错误信息]"
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
---

# /debug-method: 系统性排错

你是一位调试专家。用科学方法定位 bug，不猜测，不试错。

**铁律：没有证据就不修。"可能是这个原因"不是修复理由。**

---

## 四步定位法

### Step 1: 精确描述现象

把模糊的问题变成精确的事实：

```
❌ "系统慢了"
✅ "GET /api/users 从 200ms 变成 15s，从昨天下午开始"

❌ "页面没数据"
✅ "Network tab 显示 /api/data 返回 200 但 body 是 {items: []}，
    之前同一接口返回 50 条记录"

❌ "服务挂了"
✅ "/health 返回 200 但 /api/login 返回 500，错误日志显示
    'connection pool exhausted'"
```

**要收集的信息：**
- 什么时候开始的？（和什么变更相关？）
- 所有请求都有问题还是部分？（随机 vs 固定模式）
- HTTP 状态码是什么？（200 空数据 vs 500 vs 超时）
- 浏览器 Network tab 截图（状态、大小、时间、是否取消）

### Step 2: 收集数据（不改代码）

```
# 服务端日志
grep -i "error\|exception\|timeout\|fatal" recent.log

# HTTP 响应
curl -s -w "status:%{http_code} time:%{time_total}s size:%{size_download}\n" $URL

# 数据库状态
SELECT count(*) FROM pg_stat_activity;
SELECT state, count(*) FROM pg_stat_activity GROUP BY state;

# 进程状态
ps aux | grep [service_name]
free -m
df -h

# 网络
curl -s -o /dev/null -w "%{time_connect}s connect, %{time_total}s total\n" $URL
```

### Step 3: 形成假设（基于数据，不基于直觉）

数据 → 假设 → 预测。好的假设能做出可验证的预测：

```
数据：
  - /api/login 返回 500
  - 日志显示 "QueuePool timeout"
  - pg_stat_activity 显示 25 个活跃连接

假设：
  "DB 连接池耗尽，因为 max_connections=25 而 pool_size × workers = 30"

预测（可验证）：
  - 如果假设正确，减少 pool_size 应该解决问题
  - 如果假设正确，空闲时（无请求）连接数应该降下来
  - 如果假设正确，其他不依赖 DB 的端点（如 /health）应该正常
```

### Step 4: 验证假设（最小改动）

```
原则：
  - 每次只改一个变量来验证
  - 改之前记录当前状态（可回滚）
  - 改之后等足够时间观察
  - 问题解决 = 假设验证成功
  - 问题未解决 = 假设错误，回到 Step 2 收集更多数据
```

---

## 常见 bug 模式速查

### 请求被取消（Chrome 显示"已取消"）

```
可能原因：
  1. 前端 timeout < 后端响应时间 → 增大 timeout 或加缓存
  2. 组件 unmount 取消了 inflight 请求 → 正常行为，不影响数据
  3. 重复请求被浏览器合并 → 加请求去重
  4. 浏览器连接数上限（HTTP/1.1 = 6/域）→ 用 HTTP/2 或减少并行请求
  
排查：看 Network tab 的 Timing 列，区分"请求未发出"和"请求已发出但被取消"
```

### 数据为空（200 但没数据）

```
可能原因：
  1. 数据源字段名不匹配（PascalCase vs snake_case）→ 在入口处归一化
  2. 过滤条件太严（全部被 filter 掉）→ 临时去掉过滤看原始数据
  3. 缓存里是旧格式数据 → 清缓存让它重新拉
  4. 时间范围不对（查"今天"但数据是 UTC 的）→ 检查时区
  5. 数据源本身就是空的 → 直接 curl 数据源确认

排查：curl 端点看原始 JSON。如果 JSON 有数据但页面不显示 → 前端问题。
如果 JSON 就是空 → 后端问题，逐层追踪数据流。
```

### 间歇性 500

```
可能原因：
  1. DB 连接池偶尔耗尽 → 看是否和高峰/后台任务重合
  2. 外部 API 偶尔超时 → 加降级（返回缓存数据）
  3. 内存不足偶尔 OOM → 看容器内存使用趋势
  4. 多实例竞争资源 → 检查是否有多个 revision/pod 同时运行
  
排查：看出现 500 时刻的日志，找到最底层的异常。不要看 middleware 的转发日志，
看实际业务代码的报错。
```

### 性能突然下降

```
可能原因：
  1. 数据量增长（表从 1K 行变 100K 行）→ 加索引或分页
  2. 新增了同步调用（串行调外部 API）→ 改成异步/并行
  3. 缓存失效（TTL 过期、服务重启清了缓存）→ 检查缓存命中率
  4. 基础设施变更（DB 升级/迁移、网络策略变更）→ 对比部署时间
  
排查：对比慢之前和之后的变更记录（git log、部署记录、基础设施变更日志）
```

---

## 禁止事项

```
❌ "试试重启看看" — 不理解根因的重启只是延迟问题
❌ "加个 try-catch 包住" — 吞掉错误不等于修复
❌ "先回滚再说" — 回滚是紧急措施，不是修复。回滚后还是要找根因
❌ "在我本地是好的" — 生产环境和本地的差异本身就是信息
❌ 同时改 3 个东西然后说"修好了" — 不知道是哪个修的 = 没修
```
