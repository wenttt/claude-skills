---
name: api-migrate
description: |
  旧接口批量迁移到新接口的系统化重构方法。处理 PDF 映射规则杂乱、配置文件重复、
  URL 后缀散落、1 对 N 接口拆分、字段改名/置空/废弃、且必须保留 get/set 赋值
  习惯（调用方和 DB 入库耦合）的复杂场景。产出：映射注册表 + 统一端点配置 +
  适配层 + 灰度开关。
user-invocable: true
argument-hint: "[PDF 路径，可省略，默认扫项目根目录]"
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

# /api-migrate: 旧接口迁移到新接口

你是一位擅长大规模重构的资深工程师。目标是把一批"旧接口调用"安全地换成"新接口调用"，
中间**零手工改动调用方的 get/set 代码**，且支持按接口粒度灰度。

**核心思想：把散乱的 PDF 映射规则固化为结构化注册表 → 用适配层吸收所有差异 → 调用方几乎不动。**

---

## 原则（先读完再动手）

0. **在原有基础上做迁移，不搞全新一套**（最重要）：
   - 绝不另起炉灶重写一套"新的 HTTP 框架 / 新的配置体系 / 新的开关系统"——风险太高、测试成本爆炸
   - 项目已经用 `RestTemplate` 就继续用，已经用 Apollo 就继续用，已经用 `@Value` 就继续用
   - 能"改名 / 分组 / 提取到一处"解决的，不要"新建一个类/包"
   - 唯一允许的新增，是适配层的翻译方法（因为新旧响应结构差异只能靠代码吸收）——而且这些方法尽可能加在**现有的 Service / Client 类**里，不是另起一个 Adapter 类
1. **PDF 不是单一事实源**：PDF 只是输入，第一步就把它转成可版本化的 YAML 注册表。以后所有改动都改 YAML，不再回头翻 PDF。
2. **调用方零改动优先**：用户明确说 get/set 不能动（DB 耦合），所以新接口响应必须先经过"翻译方法"变成旧 DTO 的形状，调用方感知不到差异。
3. **按接口粒度灰度**：in-progress 的接口先不迁移，已确认的才切。**用项目已有的开关机制**（Apollo / Nacos / `@ConditionalOnProperty`），不自建。
4. **先清点，再动手**：改代码之前先有一份完整的"调用点清单"。改到一半才发现漏了一处是最常见的翻车原因。
5. **字段必须 100% 覆盖**：旧 DTO 的每个字段，必须在注册表里明确落到一个状态（mapped/nulled/dropped），不允许"不知道"。

---

## Phase 0: 自动识别 PDF 和技术栈（你来做，不问用户）

### 0.1 找 PDF 映射文件

```bash
# 优先用用户传入的参数；没传就扫根目录
ls -1 *.pdf 2>/dev/null
```

**判定规则**：
- 用户通过参数指定了路径 → 直接用
- 根目录只有一个 PDF → 就用它
- 多个 PDF → 用 AskUserQuestion 让用户选
- 没有 PDF → 用 AskUserQuestion 让用户提供路径，或让用户直接把映射规则粘贴过来

然后 `Read` 这个 PDF，把里面的新旧接口对照提取出来。**PDF 常见格式**：
- 每个接口一页或一段，标题是旧接口名（注意：旧接口 URL 里可能包含 `ods` 这类前缀字符，只是命名约定，和数仓 ODS 层无关）
- 下面有"字段对照表"：旧字段名 / 新字段名 / 说明（改名/废弃/不用）
- 可能标注"已上线 / 灰度中 / 待定" → 对应注册表里的 status

### 0.2 技术栈扫描

```bash
ls pom.xml build.gradle 2>/dev/null               # Java 构建工具
grep -l "spring-boot" pom.xml build.gradle 2>/dev/null

# HTTP 客户端（决定适配器怎么写）
grep -rn "RestTemplate\|FeignClient\|WebClient\|OkHttpClient\|HttpClient" --include="*.java" -l | head -5

# 配置中心（决定灰度开关怎么接）
grep -rn "@ConfigurationProperties\|@Value\|Apollo\|Nacos" --include="*.java" -l | head -5
```

### 0.3 只在信息真不够时才问用户

**用 AskUserQuestion 补问（一次问完，别来回打断）**：

- PDF 里看不清楚的字段对照（比如"说明"栏写得含糊）
- 灰度开关走什么机制（Apollo / Nacos / `@ConditionalOnProperty`）
- 迁移的上线节奏有没有硬 deadline

**已经能从代码里扫出来的东西，不要问。**

---

## Phase 1: 把 PDF 映射规则转成结构化注册表

这是整个迁移的基石。所有后续步骤都依赖这份注册表。

### 1.1 读 PDF，输出 YAML

让用户把 PDF 交给你（或你用 Read 读 PDF）。输出一份 `api-migration-registry.yaml`：

```yaml
# api-migration-registry.yaml — 唯一事实源
# 每新加一个迁移项就在这里加一条。in_progress 的先留着别迁。

migrations:
  - id: user-profile-001                  # 稳定 ID，日志/开关里用
    status: ready                         # ready | in_progress | skip | done
    old:
      endpoint: /api/v1/user/profile      # 旧接口路径
      method: GET
      response_dto: UserProfileDTO        # Java 类名
    new:
      # 1 对 1
      - endpoint: /api/v2/user/info
        method: GET
    field_map:
      # 旧字段名: 新字段来源（或 null / drop）
      userId: "$.data.id"                 # 改名：新接口里叫 id
      userName: "$.data.name"
      nickName: null                      # 新接口废弃，置 null
      avatar: "$.data.avatarUrl"
      legacyScore: drop                   # 新接口不用这个字段，旧 DTO 里也不再赋值

  - id: order-detail-002
    status: ready
    old:
      endpoint: /api/v1/order/detail
      method: GET
      response_dto: OrderDetailDTO
    new:
      # 1 对 N —— 旧接口一次查，新接口要调两个
      - endpoint: /api/v2/order/base
        method: GET
        alias: base
      - endpoint: /api/v2/order/items
        method: GET
        alias: items
    field_map:
      orderId: "base.$.orderId"
      customerName: "base.$.customer.name"
      itemList: "items.$.list"            # 从另一个接口拿
      totalAmount: "base.$.amount"
      oldDiscountRule: null               # 废弃字段

  - id: inventory-sync-003
    status: in_progress                    # PDF 说还没定稿 —— 不迁
    old:
      endpoint: /api/v1/inventory/sync
```

### 1.2 注册表自检清单

生成 YAML 后，逐条检查（你自己做，不问用户）：

- [ ] 每个 migration 的 `old.response_dto` 的每个字段，在 `field_map` 里都出现过（不允许漏）
- [ ] `field_map` 的 value 只能是三种形式之一：JSONPath 字符串 / `null` / `drop`
- [ ] `status: in_progress` 的项只保留 `old` 段即可，`new`/`field_map` 可以留空
- [ ] `id` 全局唯一

**漏字段 = 迁移后静默丢数据 = 事故。必须严格检查。**

### 1.3 把 YAML 交给用户确认

```
我根据 PDF 生成了 N 条迁移规则，其中：
- ready: X 条（可以迁移）
- in_progress: Y 条（跳过）
- 疑似漏字段: Z 条 ——【列出来，请用户补充】

请确认 api-migration-registry.yaml。确认后我开始 Phase 2。
```

---

## Phase 2: 清点现状 —— 建立调用点清单

在改任何代码前，先知道要改多少地方。

### 2.1 扫配置文件

```bash
# 找所有旧接口路径在配置里的出现
grep -rn "/api/v1/" --include="*.yml" --include="*.yaml" --include="*.properties" --include="*.xml" .

# 统计重复度 —— 同一个路径在多少个 config key 下被定义
grep -rhn "/api/v1/" --include="*.yml" --include="*.properties" | sort | uniq -c | sort -rn | head -20
```

**预期发现**：同一个旧接口 URL 被不同的 config key 引用了 N 次（用户原话"重复度很高"）。Phase 3 要收敛成一个。

### 2.2 扫 Java 代码的调用点

```bash
# 散落的 URL 后缀（@Value 拼接 / 硬编码）
grep -rn "@Value.*api\." --include="*.java" .
grep -rn "\"/api/v1" --include="*.java" .
grep -rn "restTemplate\|webClient\|feignClient\|okHttpClient" --include="*.java" . | head -30

# 按旧接口路径反查所有调用点（对每条 status=ready 的 migration 跑一遍）
grep -rn "旧接口路径片段" --include="*.java" --include="*.yml" .
```

### 2.3 扫字段消费方（废弃字段的影响范围）

用户说新接口会让某些字段"置 null"或"不用了"。要扫一遍旧代码里这些字段被怎么用的 —— 尤其是 `if (dto.getXxx() != null)` 这种判断分支，置 null 会改变执行路径。

```bash
# 对每个会被置 null / drop 的字段，找所有 get 点
grep -rn "\.getNickName\(\)\|\.getOldXxx\(\)" --include="*.java" -B1 -A3 | head -40

# 入库点 —— DTO get/set 后紧跟 insert/update 的位置
grep -rn "insert\|update\|save" --include="*.java" --include="*.xml" -B2 | grep -E "getXxx|setXxx" | head -20
```

### 2.4 输出清单（Markdown 表格）

```
## 调用点清单

| migration_id | 旧接口 | 配置引用 | Java 调用点 |
|---|---|---|---|
| user-profile-001 | /api/v1/user/profile | application.yml:23, 45 | UserService.java:88, ProfileController.java:41 |
| order-detail-002 | /api/v1/order/detail | application.yml:56 | OrderService.java:120 |

## 字段用量（重点是会被置 null / drop 的）

| migration_id | 字段 | 映射状态 | 旧代码使用点 | 风险 |
|---|---|---|---|---|
| user-profile-001 | nickName | null | ProfileController:67 显示给前端 / UserDao:23 入库 | ⚠️ 置 null 后前端显示空白 + 入库列变 null |
| order-detail-002 | oldDiscountRule | null | OrderCalc:34 参与金额计算 | 🔴 置 null 会 NPE，必须先改 OrderCalc |
| order-detail-002 | legacyScore | drop | 无使用 | 🟢 安全 |
```

**这份清单必须让用户 Review。遗漏的使用点 = 线上事故。**

---

## Phase 3: 梳理现有配置（原地清理，不新建一套）

解决"配置文件重复 + URL 后缀散落"问题。**目标是让杂乱的配置变规律，不是换一套机制。**

### 3.1 先看项目现在怎么组织配置

```bash
# 看看现有的配置风格 —— 决定怎么收敛
grep -rn "@Value" --include="*.java" | head -20
grep -rn "@ConfigurationProperties" --include="*.java" | head -10
ls src/main/resources/*.yml src/main/resources/*.properties 2>/dev/null
```

根据扫描结果分情况处理：

**情况 A：项目已经有 `@ConfigurationProperties` 类**（比如 `ApiConfig` / `ExternalApiProperties`）
→ 往这个已有的类里加新接口的 URL 字段，不新建类

**情况 B：项目全靠散落的 `@Value`**
→ 每个业务模块用一个 `@ConfigurationProperties` 类聚合（命名跟项目现有风格一致），不要做"全局统一 EndpointRegistry"

**情况 C：有一半 `@Value` 一半 `@ConfigurationProperties`**
→ 只梳理这次迁移涉及的接口，其他的不动

### 3.2 配置去重的三步做法（原地改）

**第 1 步：找出重复的配置 key**

```bash
# 同一个 URL 在 yml 里被几个 key 重复定义
grep -rhn "baseUrl\|base-url\|host" --include="*.yml" --include="*.properties" | sort
```

**第 2 步：保留一个主 key，其他 key 改成引用它**

很多配置框架（Spring）支持 `${主key}` 引用。先让杂乱的配置指向同一个源，再慢慢清理引用点。不是一次全删。

```yaml
# 原来
service-a:
  user-url: https://api.example.com/api/v1/user
service-b:
  user-api: https://api.example.com/api/v1/user   # 重复

# 梳理后（保留两个 key，但值引用同一个）
external:
  base-url: https://api.example.com
service-a:
  user-url: ${external.base-url}/api/v1/user
service-b:
  user-api: ${external.base-url}/api/v1/user      # 还能用，改引用即可
```

**第 3 步：确实没人用的 key 才删**

用 `grep` 确认一个 key 完全没被引用，才删除。宁可多留几个注释掉的旧 key 等下次清理，也别手抖删了线上还在读的配置。

### 3.3 散落的 `@Value` 怎么处理

**只改这次迁移涉及的 `@Value`，其他不动。**

- 如果一个 Service 类里有 5 处 `@Value("${xxx.url}")`，其中 2 处是本次迁移的接口，**只把这 2 处挪到一个 `@ConfigurationProperties` 里，剩下 3 处保留**
- 不要做"顺手重构"。本次迁移范围之外的代码一行都不动
- 改完这 2 处立即跑测试，再进下一条 migration

---

## Phase 4: 翻译方法 —— 写在现有类里，不新建 Adapter 包

这是整个方案必须新增的唯一代码（新旧响应结构差异只能靠代码吸收）。**但位置要选好：加在现有的 Service / Client 类里，不要另起一个 `adapter/` 包。**

### 4.1 首选：加在现有调用方法里

假设项目现在这样：

```java
// 现有代码 UserService.java
@Service
public class UserService {
    @Autowired RestTemplate restTemplate;
    @Value("${user.api.url}") String userApiUrl;

    public UserProfileDTO getProfile(Long userId) {
        return restTemplate.getForObject(userApiUrl + "?userId=" + userId, UserProfileDTO.class);
    }
}
```

**改成**（改同一个方法，不新建类）：

```java
@Service
public class UserService {
    @Autowired RestTemplate restTemplate;
    @Value("${user.api.url}") String userApiUrl;           // 保留
    @Value("${user.api.new-url}") String userApiNewUrl;    // 新增
    @Value("${migration.user-profile-001:false}") boolean useNewApi;  // 开关

    public UserProfileDTO getProfile(Long userId) {
        if (useNewApi) {
            return fetchFromNew(userId);
        }
        // 旧路径：一行都没动
        return restTemplate.getForObject(userApiUrl + "?userId=" + userId, UserProfileDTO.class);
    }

    // 新增的私有方法，只做"调新接口 + 翻译成旧 DTO"
    private UserProfileDTO fetchFromNew(Long userId) {
        NewUserInfoResponse resp = restTemplate.getForObject(
            userApiNewUrl + "?id=" + userId, NewUserInfoResponse.class);

        UserProfileDTO dto = new UserProfileDTO();
        dto.setUserId(resp.getData().getId());             // 改名
        dto.setUserName(resp.getData().getName());         // 改名
        dto.setNickName(null);                             // 废弃，置 null
        dto.setAvatar(resp.getData().getAvatarUrl());      // 改名
        // legacyScore: drop —— 不赋值
        return dto;
    }
}
```

**关键点：**
- 没有新建 `UserProfileAdapter` 类
- 调用方 (`userService.getProfile(...)`) 的签名没变，所有用到它的地方一行都不用改
- 旧路径原封不动，出问题把 `migration.user-profile-001` 开关关掉立即回滚

### 4.2 什么时候才新建类

只有这两种情况才考虑新增一个类：

1. **1 对 N 场景**，翻译逻辑超过 30 行，塞在原方法里会让 Service 膨胀
2. 翻译逻辑被 2+ 个地方复用

其他情况一律写在现有类里。**不要为了"代码好看"新建 Adapter 包**。

### 4.3 1 对 N 的翻译

如果字段分散在多个新接口，且逻辑较长，可以抽一个私有方法（仍在原类里）：

```java
public OrderDetailDTO getDetail(Long orderId) {
    if (useNewApi) {
        return fetchAndMergeFromNew(orderId);
    }
    return restTemplate.getForObject(oldUrl + "?id=" + orderId, OrderDetailDTO.class);
}

private OrderDetailDTO fetchAndMergeFromNew(Long orderId) {
    // 顺序调用即可，除非有性能要求才用并行
    OrderBaseResponse base = restTemplate.getForObject(orderBaseUrl + "?id=" + orderId, OrderBaseResponse.class);
    OrderItemsResponse items = restTemplate.getForObject(orderItemsUrl + "?orderId=" + orderId, OrderItemsResponse.class);

    OrderDetailDTO dto = new OrderDetailDTO();
    dto.setOrderId(base.getOrderId());
    dto.setCustomerName(base.getCustomer().getName());
    dto.setItemList(items.getList());
    dto.setTotalAmount(base.getAmount());
    dto.setOldDiscountRule(null);
    return dto;
}
```

### 4.4 字段覆盖自检

每个翻译方法写完，对照 registry 里对应 migration 的 `field_map`：

```
UserProfileDTO 有 5 个字段：userId / userName / nickName / avatar / legacyScore
field_map 覆盖情况：
  ✅ userId  → mapped from $.data.id
  ✅ userName → mapped from $.data.name
  ✅ nickName → null
  ✅ avatar → mapped from $.data.avatarUrl
  ✅ legacyScore → drop
覆盖率：5/5 ✅
```

**任何 ❌ 都必须回到 Phase 1 补 registry，不能在代码里偷偷留空。**

---

## Phase 5: 灰度开关 —— 用项目已有机制，不自建

先看项目现在有什么：

```bash
grep -rn "Apollo\|Nacos\|@ConditionalOnProperty\|FeatureFlag" --include="*.java" -l | head -5
```

**按现有机制选方案，不要自建 `MigrationSwitch`**：

### 情况 A：项目已有 Apollo / Nacos
直接在 Apollo / Nacos 里加配置，用 `@Value` 注入即可（Apollo 支持动态刷新）：

```yaml
# Apollo 配置
migration.user-profile-001: false    # 默认关
migration.order-detail-002: false
```

```java
@Value("${migration.user-profile-001:false}")
private boolean useNewUserProfile;
```

### 情况 B：项目用 Spring 原生配置
同样用 `@Value`，放在 `application.yml`：

```yaml
migration:
  user-profile-001: false
  order-detail-002: false
```

### 情况 C：已有 feature flag 框架
按框架的 API 调用即可，不要绕过它自己造。

**开关命名规范**：`migration.<migration_id>`，key 和 registry 里的 `id` 完全一致。

**上线节奏**：

1. 所有开关默认 false，合并代码（纯新增代码 + 新增 else 分支，零行为变化）
2. 测试环境逐个打开，对比新旧响应
3. 生产环境按 migration_id 一个一个打开，每个观察 1-2 天
4. 全部稳定后，删除 `fetchFromNew` 之外的旧路径代码 + 旧的 `@Value` 配置

---

## Phase 6: 验证

### 6.1 对比测试（强烈推荐）

加一个"双跑对比"模式，旧新同时调，比对结果。**直接写在同一个方法里**，不单独搞"对比框架"：

```java
public UserProfileDTO getProfile(Long userId) {
    if (useNewApi) {
        return fetchFromNew(userId);
    }

    UserProfileDTO oldDto = restTemplate.getForObject(...);  // 旧路径

    // dry-run：开关开启时额外跑一次新接口做对比（不影响返回值）
    if (dryRun) {
        try {
            UserProfileDTO newDto = fetchFromNew(userId);
            log.info("migration-diff user-profile-001: old={}, new={}", oldDto, newDto);
        } catch (Exception e) {
            log.warn("migration-diff failed", e);
        }
    }
    return oldDto;
}
```

跑几天日志，看 diff 有没有意料之外的不一致（除了已知的 null/drop 字段）。

### 6.2 退出标准

一条 migration 可以标 `status: done` 的条件：

- [ ] 生产开关已打开 ≥ 1 周
- [ ] 无相关报错/报警
- [ ] dry-run 日志里无意外 diff
- [ ] 旧路径代码 + 旧 `@Value` 已删除
- [ ] 旧接口服务端确认已下线或计划下线

---

## 常见翻车点

1. **只改代码不改配置**：旧 `@Value` 留着没人用，迁移完忘了删，后人以为还在用
2. **字段静默漏**：适配器里某个字段忘了 set，默认值是 0/""/null，DB 里写脏数据
3. **1 对 N 的新接口失败处理**：某一个新接口超时，整个适配器抛异常还是降级？必须明确
4. **in_progress 的被"顺手也改了"**：registry 里 status 不是 ready 就坚决不动
5. **废弃字段的判断分支**：字段被置 null 后，`if (dto.getNickName() != null)` 这种分支走向会变 —— Phase 2.3 必须扫完
6. **字段类型不一致**：新接口 `amount` 是 `BigDecimal`，旧 DTO 是 `Double` —— 精度丢失或 ClassCastException
7. **空值语义差异**：旧接口返回 `""`，新接口返回 `null`（或反过来）—— DB 非空约束、字符串比较逻辑会炸
8. **灰度开关默认 true**：一定要默认 false，走旧路径，显式开启

---

## 输出节奏

你对用户的交付分四次：

1. **交付一：registry YAML + 风险点清单** → 用户 review 确认
2. **交付二：挑最简单的一条 migration，在现有 Service 里加翻译方法 + 开关** → 用户 review 代码风格，确认"在现有类里改"的方式 OK
3. **交付三：批量做其他 migration + 配置去重** → 用户跑测试
4. **交付四：退场清理清单**（哪些旧代码/旧 `@Value`/旧 yml key 要删） → 全部 done 后执行

**不要一次性把所有代码都写完。每次交付后等用户反馈再继续。**

**原则复习**：每一步都在问"这个改动能不能在原有代码上做？"能 → 就在原地改。不能 → 写出新增的最小增量。绝不批量新建一整套框架。
