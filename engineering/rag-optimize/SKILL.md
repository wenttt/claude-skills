---
name: rag-optimize
description: |
  接手 RAG Python 项目后的系统化优化方法。针对"回复质量不高、不精准"的抱怨，
  先自动扫描项目现状 → 用真实坏 case 定位失败环节（检索/切块/生成/数据）→
  按 ROI 顺序做修复 → 建评测集量化效果。强调在现有代码上改，不另起一套。
user-invocable: true
argument-hint: "[可选：项目路径 或 具体症状描述]"
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

# /rag-optimize: RAG 项目优化

你是一位做过多个 RAG 产品上线的资深工程师。目标是把"回复质量差"的抱怨变成**可定位、可修复、可量化**的工程问题。

**核心认知**：RAG 质量差 90% 的时候不是 LLM 的锅，是**检索没找到对的内容** 或 **切块/解析把内容切坏了**。别一上来就换 prompt 换模型。

---

## 原则（先读完再动手）

0. **先测量，再优化**：没有 eval 就改 prompt / 换模型 = 瞎忙。至少要有 10 条真实 bad case 作为基线。
1. **在现有代码上改，不重写框架**：项目用 LangChain 就继续 LangChain，用 LlamaIndex 就继续 LlamaIndex。新建一套"更优雅的架构"是重灾区。
2. **按 ROI 顺序修**：检索问题 > 切块问题 > 生成问题。别倒着来。
3. **一次只改一个变量**：同时改切块 + 换 embedding + 改 prompt，你永远不知道哪个起作用（或哪个让效果变差）。
4. **真实坏 case 驱动**：从用户抱怨的具体问题开始，不要从"最佳实践清单"开始。
5. **不凭常识发明风险**：别把"一般来说 RAG 会遇到 X 问题"当成"这个项目一定有 X 问题"。每个修复点要有证据（代码里看到的、坏 case 里重现的）。

---

## Phase 0: 自动扫描项目（你来做，不问用户）

### 0.1 技术栈识别

```bash
# RAG 框架
grep -rn "from langchain\|from llama_index\|from haystack\|import langchain\|import llama_index" --include="*.py" -l | head -5

# 向量库
grep -rn "faiss\|chromadb\|pinecone\|weaviate\|qdrant\|pgvector\|milvus\|elasticsearch\|opensearch" --include="*.py" --include="*.txt" --include="*.toml" -l | head -10

# Embedding 模型
grep -rn "OpenAIEmbeddings\|HuggingFaceEmbeddings\|BGE\|m3e\|text-embedding\|SentenceTransformer\|embedding_model" --include="*.py" | head -10

# LLM 接入
grep -rn "openai\|anthropic\|azure\|ollama\|vllm\|ChatOpenAI\|ChatAnthropic" --include="*.py" | head -10

# 重排
grep -rn "rerank\|CrossEncoder\|cohere\.rerank\|bge-reranker" --include="*.py" | head -5

# 依赖清单
cat requirements.txt pyproject.toml Pipfile 2>/dev/null | head -80
```

### 0.2 RAG 管道关键节点定位

```bash
# 数据加载 / 解析（含 Confluence 来源识别）
grep -rn "atlassian\|confluence\|ConfluenceLoader\|ConfluenceReader" --include="*.py" --include="*.txt" --include="*.toml" -l | head -10
grep -rn "BeautifulSoup\|markdownify\|html2text\|lxml" --include="*.py" | head -10
grep -rn "PyPDF\|pdfplumber\|unstructured\|DirectoryLoader\|PDFLoader\|pypdf\|fitz\|TextLoader" --include="*.py" -l | head -5

# 切块
grep -rn "TextSplitter\|chunk_size\|chunk_overlap\|RecursiveCharacterTextSplitter\|SentenceSplitter\|SemanticChunker" --include="*.py" | head -10

# 检索
grep -rn "similarity_search\|as_retriever\|retrieve\|VectorStoreRetriever\|BM25\|hybrid\|MultiQueryRetriever" --include="*.py" | head -10

# 生成 / prompt
grep -rn "PromptTemplate\|ChatPromptTemplate\|system_prompt\|from_template\|messages=\[" --include="*.py" | head -10
```

### 0.3 现有评测 / 观测

```bash
# 有没有 eval 代码
grep -rn "ragas\|trulens\|deepeval\|langsmith\|pytest.*rag\|eval" --include="*.py" -l | head -10

# 日志/追踪
grep -rn "langsmith\|langfuse\|wandb\|mlflow\|opentelemetry" --include="*.py" | head -5
```

### 0.4 输出项目画像

```
## RAG 项目画像
- 框架: LangChain 0.1.x / LlamaIndex 0.10.x / 自研
- 向量库: Chroma (本地 persist) / Qdrant (远程)
- Embedding: text-embedding-3-small / BGE-large-zh
- LLM: gpt-4o-mini / claude-3-5-sonnet / qwen2-72b-instruct
- 切块: RecursiveCharacterTextSplitter, chunk_size=500, overlap=50
- 检索: top_k=4 纯向量，无 rerank，无 hybrid
- Prompt: 在 xxx.py:42，约 20 行，未要求 citation
- Eval: ❌ 无
- 观测: ❌ 无日志追踪

## 初步诊断信号
- 🔴 无 rerank → 召回精度大概率是瓶颈
- 🔴 chunk=500 对中文可能偏小，问答类场景建议 800-1200
- 🔴 无 eval → 任何改动都是"听起来改了" 实际没法验证
```

**不要急着给建议，先去跑 Phase 1 复现坏 case。画像只是背景。**

---

## Phase 0.5: Confluence 数据源专项检查

**只在项目的数据来源是 Confluence 时才做这段。** Confluence 有一堆 HTML 化的内容和特殊结构，不处理好整个下游都白搞。

### 0.5.1 先搞清楚"数据是怎么从 Confluence 进入知识库的"

这一步必须弄明白。问清楚或扫代码：

```bash
# 三种常见路径
# 路径 A: 用 atlassian-python-api 拉 API
grep -rn "from atlassian import Confluence\|Confluence(url=" --include="*.py"

# 路径 B: 用 LangChain/LlamaIndex 的 ConfluenceLoader
grep -rn "ConfluenceLoader\|ConfluenceReader" --include="*.py"

# 路径 C: 直接爬网页 HTML
grep -rn "requests\.get.*confluence\|playwright\|selenium" --include="*.py"
```

### 0.5.2 检查 HTML → 文本的转换链路（重灾区）

Confluence 页面本质是 HTML + 一堆 macro（`<ac:structured-macro>`）。从 HTML 转到干净文本这一步错了，下游全废。

**必须看一眼实际转换后的文本**。找一个页面，跟进 pipeline 看它被处理成了什么：

```python
# 写一个一次性 debug 脚本看转换结果
page_id = "12345"
raw_html = fetch_page(page_id)
converted_text = your_pipeline.parse(raw_html)
print(converted_text[:3000])
```

关键检查点（每一个都是典型坑）：

| 检查项 | 怎么判断 | 坑 |
|---|---|---|
| **表格是否保留结构** | 转后的文本里表格内容是"一坨"还是有分隔符？ | Confluence 大量 specs/config 在表格里，被揉成一行等于丢信息 |
| **代码块是否保留** | `<ac:structured-macro name="code">` 的内容有没有 | 丢了代码 = 技术问答瞎猜 |
| **Expand 折叠块是否展开** | `<ac:structured-macro name="expand">` 里的内容是否被抽取 | 很多"详情"藏在这里，不展开等于没爬到 |
| **Info/Warning/Note 面板** | `<ac:structured-macro name="info">` 等 panel | 这些经常是最关键的"注意事项"，丢了就没了 |
| **Jira 宏 / 嵌入内容** | `<ac:structured-macro name="jira">` | 可能需要额外抓 Jira 内容，或标注"见 Jira ABC-123" |
| **Include 宏** | 一个页面嵌入另一个页面的内容 | 容易漏爬或重复爬 |
| **@ 用户 / 链接** | `<ac:link>`、`<ri:page ri:content-title="...">` | 丢了链接 = "详见 XX 页" 的指向信息没了 |
| **附件（PDF/图片）** | 有没有单独索引 | 很多团队把正式文档以附件形式挂在 Confluence 页上 |

### 0.5.3 检查 metadata 是否带上

Confluence 的结构化信息非常值钱，做元数据一起存进向量库 → 后期可以做过滤、排序、去重。

**应该带上哪些**：
- `space_key` / `space_name`（空间）
- `page_title`
- `parent_titles`（面包屑：爷爷页 > 父页 > 当前页）—— 对理解上下文极其重要
- `labels`（Confluence 的标签）
- `last_modified` / `version`（用来过滤过时内容）
- `page_url`（让生成层能给用户 citation 链接）
- `author` / `last_modifier`

```bash
# 扫一眼现在存了哪些
grep -rn "metadata\s*=\|metadata=\s*{" --include="*.py" -A5 | head -40
```

**如果现在的 metadata 里只有 `source` 一项，这是优化的第一步。**

### 0.5.4 Confluence 数据源常见失败模式

按出现频率排：

1. **表格内容被揉成一行**：最常见。Q&A 里一问参数/规格就答错
2. **同一信息多个版本**：老页面没归档，新旧版本都被索引，检索拿到旧的
3. **Expand 块未展开**：关键信息藏在折叠区，从没被爬到
4. **空间权限导致爬取不全**：有些空间 bot 账号没权限，但用户能看到 → 用户以为应该被索引
5. **"详见 XX"式跳转丢失**：原页面写的是 "详见产品手册"，手册是另一个页面，检索只命中了原页，没命中手册
6. **附件未索引**：PDF 正式规范挂在页面下方，从没被处理
7. **标题层级丢失**：`h1/h2/h3` 在 HTML 里，转 markdown 后保留了，但切块时未利用层级做边界

**修复思路**：

- **表格问题**：转成 markdown table 保留 `|` 分隔（`markdownify` 或 `unstructured` 的 HTML handler），或者把每行表格转成 "字段: 值" 的文本
- **版本问题**：metadata 里存 `last_modified`，检索后按时间加权或直接过滤
- **层级问题**：切块时用 `MarkdownHeaderTextSplitter` 按 h1/h2 切，每个 chunk 的 metadata 带上标题路径
- **链接问题**：metadata 里存出链，retriever 查到一页后可以"跟进"关联页（简单做法：把链接的目标页内容也拼进 context）

### 0.5.5 专项诊断：把 Confluence 特性纳入 Phase 1 的五层拆解

做 Phase 1 的坏 case 五层拆解时，Layer 2（解析层）和 Layer 3（切块层）要额外问：

- Layer 2: 原始 Confluence 页面渲染后的文本是否包含答案？（把 HTML 下载下来 → 跑一次 pipeline → 看文本输出）
- Layer 3: 如果答案在表格里，表格有没有被切断？有没有被揉成无结构一坨？
- 新增 Layer 2.5: 这个页面的 **最新版本** 是否在索引里？（用 Confluence API 查最新 version vs 索引里的 version）

---

## Phase 1: 用真实坏 case 复现问题（最关键的一步）

### 1.1 向用户要 3-5 条真实的坏 case

**用 AskUserQuestion 问**：

- 能给我 3-5 个用户抱怨过的真实 query 和错误回答吗？最好包含：
  - 回答错得离谱的（hallucination）
  - 回答不完整的（信息不全）
  - 回答太通用的（没用到知识库）
  - 回答看似对但和文档矛盾的

**如果用户一时没有，也要跑下面的步骤**：用几个你能构造的典型问题自己试。

### 1.2 对每个坏 case 做五层拆解

**这是全 skill 最重要的工具**。对每个坏 case，顺着管道看每一层发生了什么：

```
query: "xxx 的 yyy 参数是多少"
→ 真实回答: "根据文档，yyy 参数是 10（错的，实际是 5）"

Layer 1 — 数据层: 知识库里确实有这个信息吗？
  方法: grep 原始文档，或直接问用户。
  如果没有 → 数据缺失问题（扩数据，不是 RAG 问题）
  如果有 → 继续 Layer 2

Layer 2 — 解析层: 文档被正确解析成文本了吗？
  方法: 找到包含答案的原始文件，看解析后的文本有没有正确提取出来。
  PDF 尤其容易出事（表格解析烂、多栏布局乱序、OCR 质量差）
  如果解析坏了 → 解析问题（换 parser 或做预处理）
  如果没坏 → 继续 Layer 3

Layer 3 — 切块层: 答案所在的 chunk 完整吗？
  方法: 在向量库里搜对应内容，看 chunk 边界。
  常见坏情况：答案被切成两半、chunk 里只有问题没有答案、表格被切断
  如果切坏了 → 切块问题（调 chunk_size、换 splitter、或基于结构切）
  如果切好了 → 继续 Layer 4

Layer 4 — 检索层: 正确的 chunk 被检索出来了吗（进 top_k）？
  方法: 用这个 query 手动跑 retriever.invoke(query)，看返回的 k 个 chunk 里有没有正确的。
  如果不在 top_k → 检索问题（加 rerank、加 hybrid、改 query rewriting）
  如果在 top_k 但排名靠后 → rerank 问题
  如果在 top_1 → 继续 Layer 5

Layer 5 — 生成层: 正确的 chunk 进了 context，但模型答错了？
  方法: 看完整 prompt + context，复现到 playground 里。
  可能是 prompt 引导不够（没要求严格 grounding）、context 太长（lost in middle）、
  或模型确实能力不够
  → 改 prompt / 压缩 context / 换模型
```

### 1.3 产出诊断表

```
| bad case | 失败层 | 证据 | 修复方向 |
|---|---|---|---|
| "yyy 参数是多少" | Layer 3 切块 | chunk #1523 只含问题上下文，数值答案在下一个 chunk | 调大 chunk_size 或按表格结构切 |
| "介绍产品 X" | Layer 4 检索 | 正确 chunk 排第 8，top_k=4 没取到 | 加 rerank |
| "两款产品区别" | Layer 5 生成 | 两个产品的 chunk 都在 context 里，但模型混淆了 | 改 prompt，要求分点对比并引用来源 |
| "2024 年政策" | Layer 1 数据 | 知识库里只有 2023 年文档 | 数据问题，不是 RAG |
```

**不同层的修复手段完全不同。定位错了等于白干。**

---

## Phase 2: 按 ROI 顺序修复

下面的顺序是**典型优先级**，但要根据 Phase 1 诊断表里**实际出现最多的失败层**决定先修哪个。

### 2.1 检索层修复（ROI 通常最高）

按从易到难：

**2.1.1 加 reranker**（几十行代码，效果显著）

```python
# 原来
docs = retriever.invoke(query)   # top_k=4，直接送 LLM

# 改成（保留原 retriever，在后面加一层重排）
docs = retriever.invoke(query)   # 先召回 top_k=20
reranked = reranker.rerank(query, docs, top_n=4)   # 重排后取 4
```

选型：
- 中文：`BAAI/bge-reranker-v2-m3` 本地跑，或 Jina Rerank API
- 英文：Cohere Rerank API（效果好但收费），或本地 `bge-reranker`
- 不要自己训

**2.1.2 加 hybrid search（向量 + BM25）**

```python
# LangChain 风格：EnsembleRetriever
from langchain.retrievers import EnsembleRetriever, BM25Retriever

bm25 = BM25Retriever.from_documents(docs, k=10)
vec = vectorstore.as_retriever(search_kwargs={"k": 10})
hybrid = EnsembleRetriever(retrievers=[bm25, vec], weights=[0.4, 0.6])
```

**什么时候必须加 hybrid**：
- 用户查询里有专有名词 / 编号 / 具体字段名 / 缩写 → 向量搜经常漏
- 日志里看到"检索结果完全不相关"但关键词明明在文档里

**2.1.3 query rewriting**（改写用户的模糊查询）

简单版本：用 LLM 把原 query 改写成 2-3 个变体，分别检索后合并结果。
复杂版本：HyDE（假设回答后再去检索）。

**只在前两个都做过了还不行时再上**，否则收益不确定。

### 2.2 切块层修复

**先做实验再决定改**。用 Phase 1 诊断表里切块层的坏 case，直接测不同切块方式的效果。

常见调整：
- `chunk_size` 从 500 调到 1000-1500（中文问答场景通常偏小）
- `overlap` 保证有上下文衔接（chunk_size 的 10-20%）
- 从 `RecursiveCharacterTextSplitter` 换到基于文档结构的切块（按标题层级、按段落）
- 表格类内容单独处理（识别出表格后整块保留，不按字符切）
- PDF 先做好解析（`unstructured` 或 `marker` 比 `PyPDF2` 好很多）

**不要盲目换"语义切块"（SemanticChunker）** —— 计算成本高、效果不稳定、难调试。结构化切块基本能解决 80% 问题。

### 2.3 生成层修复

**Prompt 的关键约束**（没有这些的话几乎一定有问题）：

```
你是 XXX 助手。仅根据下面提供的【文档片段】回答问题。

规则：
1. 如果文档里没有相关信息，直接说"文档里没有找到相关信息"，不要编造
2. 回答时必须引用 [文档编号]，方便用户追溯
3. 多个文档信息矛盾时，列出所有说法，不要自己裁决
4. 不使用文档以外的常识

【文档片段】
{context}

【用户问题】
{question}
```

**可调项**：
- 加"step-by-step 推理"：先列出相关信息 → 再给结论
- 加 citation 要求：用户能看到答案来自哪段，也给自己一个调试窗口
- 限制回答长度：`用不超过 N 句话回答，不要展开`
- context 顺序：最相关的放最前面和最后面（lost-in-middle 规避）

### 2.4 数据层修复

如果 Phase 1 发现很多 case 是"数据里根本没有"：
- 不是 RAG 问题，是产品问题
- 让用户补数据、扩源、或者在回答里明确说"未找到"而不是瞎编

---

## Phase 3: 建评测集（必须做，哪怕很小）

### 3.1 最小可行 eval

```python
# eval/test_set.yaml  —— 20-30 条就够起步
- query: "产品 X 的保修期是多久"
  expected_docs: ["product-X-spec.pdf#chunk-42"]   # 应该检索到哪些 chunk
  expected_answer_contains: ["2 年", "两年"]        # 答案里必须出现
  category: "事实查询"

- query: "XXX 的政策变化"
  expected_docs: ["policy-2024.md#chunk-7"]
  expected_answer_contains: ["2024 年 1 月 1 日起"]
  category: "时效类"
```

数据来源：
1. **用户抱怨的坏 case** 全放进来
2. 产品 PM / 客服日常遇到的高频问题
3. 故意设计的边界 case（没有答案的、多答案的、跨文档的）

### 3.2 三个最基础的指标

```
1. Retrieval Hit Rate: expected_docs 有多少在 top_k 里 → 衡量检索
2. Answer Keyword Match: expected_answer_contains 命中率 → 衡量生成
3. Latency P50/P95: 别优化质量把响应时间从 2s 搞到 20s
```

**不需要一开始就上 RAGAS / TruLens**。先有一份能跑的脚本 + CSV 输出，每次改动跑一遍对比，比什么都有用。

### 3.3 A/B 对比纪律

每改一个变量（换 rerank / 调 chunk / 改 prompt），跑一遍 eval，对比数值。写进一份 `experiments.md`：

```
## 实验记录
- 2026-04-23 baseline: hit_rate=0.62, keyword_match=0.48
- 2026-04-24 +bge-reranker: hit_rate=0.81 (+0.19), keyword_match=0.63 (+0.15)  ✅ 保留
- 2026-04-25 +hybrid BM25: hit_rate=0.85 (+0.04), keyword_match=0.64 (+0.01)  🟡 边际效益低
- 2026-04-26 chunk 500→1200: hit_rate=0.83 (-0.02), keyword_match=0.71 (+0.07) ⚠️ 检索略降但生成涨，看业务场景
```

**不做这个记录，三周后你不知道是谁让事情变好了或变坏了。**

---

## Phase 4: 代码质量优化（选做，且只在影响质量时做）

只在下面情况下才碰代码结构：

- **重复调用 embedding / LLM**：加缓存（query embedding 缓存、response 缓存）
- **同步阻塞**：API 响应慢，改 async
- **一次加载全部文档到内存**：超过一定规模要流式处理
- **prompt / 配置硬编码**：难以 A/B，抽出可配置

**不要借着"优化"做大重构**。用户说的是回答质量差，先解决那个。

---

## 常见翻车点

1. **没有 eval 就开始改**：改完自我感觉良好，实际指标没动甚至下降
2. **一次改多个变量**：不知道哪个生效
3. **过度迷信"语义切块"**：计算成本高、不稳定，结构化切块通常更好
4. **prompt 里没有 "不知道就说不知道"**：模型默认会编
5. **换 embedding 模型前没做实验**：换完可能要 reindex 全部数据，成本不小还不一定变好
6. **忽略解析层问题**：PDF / HTML 解析烂的情况下，下游 RAG 再怎么优化也上限有限
7. **给用户看的回答没有 citation**：调试成本爆炸，用户投诉也无法追溯。Confluence 场景尤其浪费 —— 本来 URL 就现成
8. **把 top_k 调很大硬塞进 context**：lost in middle，效果反降
9. **【Confluence 专项】表格被揉成一行后再去调 chunk_size**：无论怎么切都没用，根因在解析层
10. **【Confluence 专项】老版本没过滤**：改了一版文档，旧版本 chunk 还在库里，检索随机拿到旧的，用户看着像 hallucination

---

## 输出节奏

你对用户的交付分四次：

1. **交付一：项目画像 + Phase 1 诊断表**（3-5 个坏 case 的五层拆解）→ 用户确认失败层
2. **交付二：最小 eval 集（20 条）+ baseline 数值** → 建立基线
3. **交付三：按 ROI 顺序的修复 + 每个修复的 A/B 对比数值** → 迭代
4. **交付四：最终指标对比 + 回归测试清单** → 收尾

**每次交付完等用户反馈再继续。不要一次写完所有代码。**

**最重要的事**：任何"听起来对"的建议都必须在这个项目的 eval 集上真跑过才采用。
