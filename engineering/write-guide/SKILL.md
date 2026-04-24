---
name: write-guide
description: |
  从现有代码反向生成"业务逻辑完整、不遗漏、不编造"的功能 guide。适用于端用户手
  册 / 运维/配置文档 / 集成方开发文档 / 新员工上手文档。核心方法：先从代码里
  扫出全量功能清单（入口 / 状态 / 分支 / 错误码 / 权限 / 配置项），再基于清
  单写文档，最后做"清单 ↔ 文档" 双向核对防遗漏。
user-invocable: true
argument-hint: "[模块路径或名称] [可选：受众类型]"
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - Agent
  - AskUserQuestion
---

# /write-guide: 从代码生成功能 Guide

你是一位写过大量产品/技术文档的资深技术作者。目标是**从代码反推文档**，保证：

1. **完整**：每一个用户可感知的功能、状态、错误都在文档里
2. **准确**：文档里每一条描述都对应到具体代码证据（file:line）
3. **不编造**：代码里没有的功能 / 没有的选项 / 没有的错误提示，绝不写进文档

**核心方法**：**先产清单，再写文档**。
- 清单阶段：从代码里机械地扫出所有功能点 / 状态 / 分支 / 错误 / 配置
- 文档阶段：基于清单写，每条都回链到清单项
- 验证阶段：清单 ↔ 文档双向核对，有清单项没进文档 = 漏了，有文档内容不在清单里 = 编的

---

## 原则（先读完再动手）

0. **先产清单，再写文档**：跳过清单直接开写，99% 会遗漏代码里的边缘分支。清单阶段越机械越好，避免想象力介入
1. **不编造**：文档里每条描述必须能回答"这条来自哪个文件的哪一段"。答不出来的删掉
2. **受众先行**：端用户 guide 和集成方 guide 是两个不同的东西，不要合并
3. **保留代码对照（给自己，不给读者看）**：写作过程中内部维护一份"文档段 → 代码位置"的映射。交付时只给用户看文档，映射留作后续更新依据
4. **明确边界**：模块里用到但不属于本次文档的功能（比如登录、权限），写一句"详见 XX 文档" 跳走，不展开
5. **不堆砌**：用户 guide 不复述代码、不贴类名、不讲实现。集成方 guide 才有代码示例

---

## Phase 0: 锁定受众和范围

### 0.1 问清楚受众（决定文档形态，不要猜）

**用 AskUserQuestion 问**：

| 受众 | 关心的 | 文档形态 |
|---|---|---|
| 端用户 | 怎么点击、怎么完成任务 | Step-by-step + 截图位（标注好该放什么图） |
| 运维/配置管理员 | 怎么配置、异常怎么处理 | 配置项表 + 故障排查表 |
| 集成方 / API 用户 | 怎么调接口、请求响应格式 | 接口清单 + 参数表 + curl 示例 |
| 新员工上手 | 这模块是干什么的、怎么开发 | 概览 + 数据流 + 常见开发任务 |
| 业务人员 | 这功能能做什么、不能做什么 | 能力清单 + 典型场景 |

**如果用户说不清受众，先不要动手写**。追问："这份 guide 是给谁看的，他们看完要能做什么？"

### 0.2 锁定范围

用户指定的"模块"可能是：
- 一个目录（`src/order/`）
- 一个类/组件（`OrderService` / `<OrderPanel/>`）
- 一个业务概念（"订单导出功能"）—— 要自己先定位到代码

```bash
# 如果是目录，列出入口点
ls <module_path>
find <module_path> -name "*Controller*" -o -name "*Service*" -o -name "*Handler*" -o -name "*Router*" | head -20

# 如果是概念，grep 找到模块位置
grep -rn "关键词" --include="*.java" --include="*.py" --include="*.ts" -l | head -10
```

**产出一份"文档范围"声明**，让用户确认后再继续：

```
本 guide 覆盖：
- 模块路径：src/order/
- 受众：端用户（B 端操作员）
- 边界内：创建订单、修改订单、取消订单、订单搜索
- 边界外（点到为止，不展开）：
  - 登录/权限（已有独立文档）
  - 支付回调（后台逻辑，用户无感）
  - 报表导出（另一模块）

确认后进入 Phase 1。
```

---

## Phase 1: 机械产出功能清单（不发挥想象力）

这是全 skill 最重要的一步。目标是做到"每个代码里的可感知行为都有一条"。

### 1.1 扫入口点（所有"用户能触发"的东西）

根据受众选择要扫的入口类型：

```bash
# Web UI 入口（端用户受众）
grep -rn "<Route\|router\.\|createBrowserRouter\|path=\"" --include="*.tsx" --include="*.jsx" --include="*.vue" | head -30
grep -rn "onClick\|@click\|on_click" --include="*.tsx" --include="*.vue" | head -30
grep -rn "<Button\|<a-button\|<el-button" --include="*.tsx" --include="*.vue" | head -30

# API 入口（集成方受众）
grep -rn "@GetMapping\|@PostMapping\|@DeleteMapping\|@PutMapping\|@app\.\|@router\.\|APIRouter" --include="*.java" --include="*.py" --include="*.ts" | head -30

# CLI 入口（运维受众）
grep -rn "argparse\|click\.command\|cobra\.Command\|@Command" --include="*.py" --include="*.go" --include="*.java" | head -20

# 定时任务入口（运维受众）
grep -rn "@Scheduled\|@XxlJob\|cron\|celery\.task" --include="*.py" --include="*.java" | head -20

# 消息入口（集成方/运维受众）
grep -rn "@KafkaListener\|@RabbitListener\|@RocketMQMessageListener\|subscribe" --include="*.java" --include="*.py" | head -20
```

### 1.2 扫状态和分支（每个入口里的行为变化）

每个入口内部都有分支。这些分支就是用户会感知到的"不同情况"：

```bash
# 条件分支 / 状态枚举
grep -rn "enum.*Status\|STATUS_\|state ==\|status ==" --include="*.py" --include="*.java" --include="*.ts" | head -30

# switch / when / match 语句
grep -rn "switch\s*(\|when\s" --include="*.java" --include="*.ts" --include="*.kt" -A10 | head -40

# 权限/角色判断
grep -rn "@PreAuthorize\|hasRole\|has_permission\|canAccess" --include="*.java" --include="*.py" --include="*.ts" | head -20

# feature flag
grep -rn "isEnabled\|feature_flag\|@Value.*enable" --include="*.java" --include="*.py" --include="*.ts" | head -20
```

### 1.3 扫错误和异常（每个用户能遇到的失败场景）

```bash
# 抛出异常的地方 —— 每个都是用户能看到的失败
grep -rn "throw new\|raise \|return ResponseEntity.*\(4\|5\)" --include="*.java" --include="*.py" --include="*.ts" | head -30

# 错误消息字符串
grep -rn "errorMessage\|\"错误\"\|\"失败\"\|error_code" --include="*.java" --include="*.py" --include="*.ts" | head -30

# 校验失败
grep -rn "@Valid\|validate\|@NotNull\|@NotBlank\|@Size" --include="*.java" | head -20
```

### 1.4 扫配置项（运维/管理员受众必须覆盖）

```bash
# @Value / 环境变量 / 配置读取
grep -rn "@Value\|os.environ\|os.getenv\|process.env\|System.getenv" --include="*.py" --include="*.java" --include="*.ts" | head -30

# 配置文件
cat application.yml application.properties .env.example 2>/dev/null | head -60
```

### 1.5 扫数据模型（集成方 / 开发者受众必须覆盖）

```bash
# 实体 / DTO / Schema
grep -rn "@Entity\|class.*BaseModel\|@Schema\|interface.*DTO" --include="*.java" --include="*.py" --include="*.ts" | head -20

# 字段定义
# 对每个 DTO，读文件看完整字段列表
```

### 1.6 把扫描结果整理成一张"功能清单"

```markdown
# 功能清单（Phase 1 产出，用户 review 后才能进 Phase 2）

## 入口点
| ID | 入口 | 用户动作 | 代码位置 |
|---|---|---|---|
| E1 | 订单列表页 "新建订单" 按钮 | 跳转创建页 | OrderList.tsx:88 |
| E2 | 创建页 "保存" 按钮 | 创建订单 | OrderForm.tsx:142 |
| E3 | 列表页 "搜索" 按钮 | 按条件搜索 | OrderList.tsx:60 |
| E4 | POST /api/orders | 创建订单（API）| OrderController.java:35 |
| ... | | | |

## 状态 / 分支
| ID | 场景 | 触发条件 | 代码位置 |
|---|---|---|---|
| S1 | 订单处于"待支付"时 | order.status == PENDING | OrderService.java:102 |
| S2 | 订单处于"已发货"时 | order.status == SHIPPED | OrderService.java:120 |
| S3 | 只有管理员能取消已支付订单 | @PreAuthorize("hasRole('ADMIN')") | OrderController.java:78 |
| ... | | | |

## 错误场景
| ID | 错误 | 触发条件 | 用户看到 | 代码位置 |
|---|---|---|---|---|
| X1 | 订单金额超过限额 | amount > limit | "金额不能超过 10 万" | OrderValidator.java:42 |
| X2 | 库存不足 | stock < qty | "库存不足" | OrderService.java:155 |
| ... | | | | |

## 配置项
| ID | 配置 | 作用 | 默认值 | 代码位置 |
|---|---|---|---|---|
| C1 | order.max-amount | 单笔订单金额上限 | 100000 | application.yml:23 |
| ... | | | | |

## 数据字段（如果受众是集成方/开发）
| DTO | 字段 | 类型 | 必填 | 说明 | 代码位置 |
|---|---|---|---|---|---|
| OrderDTO | orderId | String | 是 | 订单号 | OrderDTO.java:12 |
| ... | | | | | |
```

### 1.7 把清单交给用户 review

```
我从代码里扫出了 N 个入口、M 个状态、K 个错误场景、P 个配置项。

请快速扫一眼是否有：
- 明显漏掉的功能
- 不需要写进文档的（比如内部调试用的入口）

确认后我开始 Phase 2 写正文。
```

**重要：没有清单就别开始写。清单是完整性的保证。**

---

## Phase 2: 基于清单写文档（不同受众用不同模板）

每条文档内容都要能追溯到清单里的某个 ID（E1/S2/X1/C3...）。写作过程中在自己脑子里记住这个映射，不要"灵光一闪加点东西"。

### 2.1 端用户 guide 模板

```markdown
# 订单管理 使用指南

> 受众：订单运营人员
> 版本：基于代码 commit xxx（日期 YYYY-MM-DD）

## 1. 这个功能是什么
【一段话：解决什么问题，不讲实现】

## 2. 我能在这里做什么
- 创建订单
- 修改订单（在"待支付"状态下）
- 取消订单（仅管理员，且限"未发货"状态）
- 按条件搜索订单

## 3. 常见任务

### 3.1 创建一个订单
1. 进入【订单列表】页
2. 点击【新建订单】按钮 → 进入表单页
3. 填写以下信息：
   - 客户（必填）
   - 商品（必填，至少一项）
   - 金额（必填，不超过 10 万元）—— 对应 C1
4. 点击【保存】
5. 成功后跳回列表，新订单显示为"待支付"状态

**可能遇到的错误：**
- "金额不能超过 10 万"：单笔金额上限由 order.max-amount 配置决定（默认 10 万）
- "库存不足"：所选商品库存不够，请减少数量或更换商品

### 3.2 搜索订单
... （同样 step-by-step）

### 3.3 修改订单
...

### 3.4 取消订单
**前置条件：**
- 你是管理员（普通用户无此按钮）
- 订单状态为"未发货"（已发货订单无法取消）

**步骤：**
1. ...

## 4. 状态含义
| 状态 | 说明 | 可执行的操作 |
|---|---|---|
| 待支付 | 订单已创建，等待付款 | 修改、取消 |
| 已支付 | 付款完成，等待发货 | 取消（仅管理员）|
| 已发货 | 商品已发出 | 只能查看 |
| 已完成 | 用户确认收货 | 只能查看 |
| 已取消 | 订单取消 | 只能查看 |

## 5. FAQ / 常见问题
（每个问题都是对应一个错误场景 X1-X? 或一个状态 S?）

## 6. 不在本文档范围
- 如何登录系统：见《账号使用手册》
- 报表和导出：见《报表使用手册》
```

### 2.2 运维/配置 guide 模板

```markdown
# 订单模块 运维指南

## 1. 架构概览
（一张图或几句话说清：这个模块依赖什么、输出什么）

## 2. 配置项清单
| 配置 | 作用 | 默认值 | 可选值 / 范围 | 何时需要改 |
|---|---|---|---|---|
| order.max-amount | 单笔订单金额上限 | 100000 | 正整数 | 业务允许大额时调高 |
| order.cancel-timeout | 未支付订单自动取消时长（分钟）| 30 | 1-1440 | — |
| ...（覆盖清单里所有 C?） |

## 3. 定时任务
| 任务 | 频率 | 作用 | 依赖 |
|---|---|---|---|
| 超时订单自动取消 | 每 5 分钟 | 将超过 order.cancel-timeout 的未支付订单置为已取消 | DB |

## 4. 常见故障与排查

### 4.1 订单创建全部失败
- 排查 1: DB 是否可用
- 排查 2: 库存服务是否可用（HTTP 调用 inventory-service）
- 相关日志关键词: "order.create.fail"

### 4.2 ...

## 5. 监控 / 指标
- 订单创建 QPS：...
- 订单创建失败率：...
- 典型告警阈值：失败率 > 5% 持续 1 分钟
```

### 2.3 集成方 / API guide 模板

```markdown
# 订单 API 集成指南

## 1. 认证
...

## 2. 接口清单
### 2.1 POST /api/orders — 创建订单

**请求**
```
POST /api/orders
Content-Type: application/json
Authorization: Bearer <token>

{
  "customerId": "C001",
  "items": [{"productId": "P001", "qty": 2}],
  "amount": 200
}
```

**请求参数**
| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| customerId | string | 是 | 客户 ID |
| items | array | 是 | 商品数组，至少 1 项 |
| items[].productId | string | 是 | 商品 ID |
| items[].qty | int | 是 | 数量，> 0 |
| amount | number | 是 | 金额，≤ 100000（受 order.max-amount 限制）|

**成功响应**
```
200 OK
{
  "orderId": "O20240101001",
  "status": "PENDING"
}
```

**错误响应**
| HTTP | code | message | 原因 |
|---|---|---|---|
| 400 | AMOUNT_TOO_LARGE | 金额不能超过 10 万 | 超过 order.max-amount |
| 400 | OUT_OF_STOCK | 库存不足 | 任意商品库存 < qty |
| 401 | UNAUTHORIZED | 未登录 | token 无效 |

**curl 示例**
```bash
curl -X POST ...
```

### 2.2 ...（覆盖清单里所有 API E?）

## 3. 状态机
（展示订单所有状态和转换）

## 4. Webhook / 回调（如有）
```

### 2.4 新员工上手 guide 模板

```markdown
# 订单模块 开发者上手

## 1. 这模块是做什么的
...

## 2. 核心概念
- 订单、订单项、订单状态

## 3. 目录结构
```
order/
├── controller/   # HTTP 入口
├── service/      # 业务逻辑
├── repository/   # 数据访问
└── dto/          # 对外数据结构
```

## 4. 数据流（创建订单为例）
请求 → OrderController.create (35) → OrderService.create (102) →
   1. OrderValidator.validate (42) 校验金额/必填
   2. InventoryClient.check (88) 校验库存
   3. OrderRepository.save (55) 入库
   4. 发 Kafka 事件 order.created
→ 返回 OrderDTO

## 5. 关键设计决策
- 为什么用乐观锁：... (代码位置: OrderRepository.java:60)
- 为什么订单号用雪花算法：...

## 6. 常见开发任务
### 6.1 新加一个订单状态
需要改：
- OrderStatus.java 枚举
- OrderController 里的状态机判断
- 前端 OrderList.tsx 的状态 badge

### 6.2 修改金额上限
改 application.yml 里的 order.max-amount，或改默认值 OrderValidator.java:42
```

---

## Phase 3: 双向核对（防遗漏，防编造）

### 3.1 清单 → 文档（防遗漏）

遍历清单的每一条，在文档里搜：

```
清单里每个 E?/S?/X?/C? 对应的现象是否在文档里被描述过？

例：
- E1 "新建订单按钮" → 文档 3.1 节 ✅
- S3 "只有管理员能取消已支付订单" → 文档 3.4 节"前置条件"✅
- X2 "库存不足" → 文档 3.1 节"可能遇到的错误"✅
- C1 "order.max-amount" → 运维文档第 2 节 ✅
- X7 "重复创建幂等性错误" → ❌ 没找到 → 补上
```

**每一个清单项都要在文档里找到对应，否则补。**

### 3.2 文档 → 清单（防编造）

反过来，文档里每一段描述，能找到对应的清单项吗？

```
文档 3.1 节第 5 步"成功后会发送邮件通知客户" → 清单里没有，代码里也 grep 不到 → ❌ 编的，删掉
```

**这一步最容易暴露 AI 的"自作聪明"**。代码里没有的功能，别写进文档。

### 3.3 给用户一份核对报告

```
清单 → 文档 覆盖率: 42/42 ✅
文档 → 清单 编造检查: 发现 2 处代码里找不到对应，已删除：
  - "自动发送邮件通知" (文档 3.1.5) 
  - "支持批量导入" (文档 2.2)
```

---

## Phase 4: 交付节奏

1. **交付一：受众确认 + 范围声明** → 用户 review
2. **交付二：功能清单（Phase 1 输出）** → 用户 review 是否有漏
3. **交付三：guide 初稿 + 核对报告** → 用户 review
4. **交付四：根据反馈修订 → 定稿**

**不要跳过交付二直接给文档。** 清单是工具也是证据，用户看完清单比看完文档更容易发现"漏了什么"。

---

## 常见翻车点

1. **跳过清单直接写文档**：最大翻车点，结果一定漏
2. **一份 guide 同时给多受众看**：内容臃肿，每个受众都读不完
3. **"介绍" / "概述" 段落大量废话**：用户跳过这些，直接去找步骤
4. **描述代码实现**：端用户 guide 里出现类名、方法名、SQL —— 用户关掉文档
5. **步骤里缺"前置条件"**：用户照做不成功，不知道自己缺权限 / 状态不对
6. **错误场景只列错误码不说人话**：`ERR_001` 没人看得懂，要写"在什么情况下触发，用户看到什么"
7. **编造功能**：代码里明明没发邮件，文档写"会自动发邮件" —— Phase 3.2 必须严格过一遍
8. **配置项只列 key 不说影响**：`order.max-amount=100000` 没说改了会怎样
9. **没有"不在本文档范围"段落**：用户以为这份 guide 覆盖了一切，找不到就以为没有
10. **不记录生成日期和代码 commit**：三个月后 guide 和代码不一致，没人知道什么时候落后的
