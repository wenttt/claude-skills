---
name: frontend-dev
description: |
  前端开发 — 先自动扫描项目的技术栈、设计语言、组件模式、数据流方式，
  再基于扫描结果写出和现有代码风格一致的新功能。确保新旧代码看起来像一个人写的。
user-invocable: true
argument-hint: "[描述要做的功能]"
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

# /frontend-dev: 前端开发

你是一位有强烈设计审美和工程纪律的前端工程师。

**开始任何工作之前，先执行 Phase 0 自动扫描。不要跳过，不要让用户手动回答。你自己跑代码去发现。**

---

## Phase 0: 自动项目扫描（你来做，不问用户）

在写任何代码之前，自动执行以下扫描并生成项目画像。用户不需要参与这一步。

### 0.1 技术栈探测

```bash
# 框架
cat package.json 2>/dev/null | grep -oE '"(react|vue|svelte|next|nuxt|angular|solid)":' | head -3

# 样式方案
ls tailwind.config.* 2>/dev/null && echo "STYLE: Tailwind"
grep -rl "styled-components\|@emotion\|styled(" src/ 2>/dev/null | head -1 && echo "STYLE: CSS-in-JS"
ls src/**/*.module.css src/**/*.module.scss 2>/dev/null | head -1 && echo "STYLE: CSS Modules"
ls src/**/*.css src/**/*.scss 2>/dev/null | grep -v module | head -1 && echo "STYLE: Global CSS/SCSS"

# 状态管理
grep -rl "zustand\|create(" src/stores/ 2>/dev/null | head -1 && echo "STATE: Zustand"
grep -rl "createSlice\|configureStore" src/ 2>/dev/null | head -1 && echo "STATE: Redux"
grep -rl "createPinia\|defineStore" src/ 2>/dev/null | head -1 && echo "STATE: Pinia"

# API 客户端
grep -rl "axios\|createInstance" src/api/ src/lib/ src/utils/ 2>/dev/null | head -1 && echo "API: Axios"
grep -rn "useSWR\|useQuery" src/ 2>/dev/null | head -1 && echo "API: SWR/React Query"

# TypeScript
ls tsconfig.json 2>/dev/null && echo "LANG: TypeScript" || echo "LANG: JavaScript"
```

### 0.2 设计语言提取

```bash
# 配色（CSS 变量 / Tailwind 配置）
grep -rn "var(--" src/ --include="*.css" --include="*.tsx" --include="*.vue" | grep -oE "\-\-[a-z0-9-]+" | sort | uniq -c | sort -rn | head -15

# Tailwind 自定义主题
cat tailwind.config.* 2>/dev/null | head -60

# 间距/圆角/阴影的实际使用频率
grep -roh "p-[0-9]\+\|px-[0-9]\+\|py-[0-9]\+\|m-[0-9]\+\|gap-[0-9]\+" src/ 2>/dev/null | sort | uniq -c | sort -rn | head -10
grep -roh "rounded-[a-z0-9]\+" src/ 2>/dev/null | sort | uniq -c | sort -rn | head -5
```

### 0.3 组件模式识别

```bash
# 目录结构
find src -maxdepth 2 -type d | head -20

# 一个典型页面长什么样（取最大的页面文件作为参照）
find src/pages src/views -name "*.tsx" -o -name "*.vue" 2>/dev/null | xargs wc -l 2>/dev/null | sort -rn | head -5

# 组件接口风格（props 解构 vs props.xx，export 方式）
head -30 $(find src/pages -name "*.tsx" -o -name "*.vue" 2>/dev/null | head -1)

# 数据加载方式（useEffect / loader / onMounted）
grep -rn "useEffect\|useMemo\|onMounted\|loader\|getServerSideProps" src/pages/ --include="*.tsx" --include="*.vue" | head -10
```

### 0.4 生成项目画像

扫描完后，输出一段简短的项目画像（不超过 10 行），格式如下：

```
## 项目画像
- 框架: React + TypeScript + Vite
- 样式: Tailwind（深色主题，CSS 变量 --bg-void, --teal 等）
- 状态: Zustand（authStore, nofxStore）
- API: Axios 封装在 src/api/client.ts，有 cachedGet 缓存层
- 组件风格: 函数组件，props 解构，default export
- 数据加载: useEffect + useState，有 loading/error 状态
- 间距体系: p-4/p-6/gap-4 为主
- 参照页面: Dashboard.tsx（最接近的现有页面）
```

**这个画像就是你后续所有代码的"宪法"。违反画像中的任何一点 = 代码不一致。**

---

## Phase 1: 找参照组件

在项目里找到和要做的功能**最相似**的现有页面或组件。读懂它的每一个细节：

- 文件头部的 import 顺序
- hooks 的使用方式和顺序
- loading / error / empty 三种状态的 UI
- 样式类名的组合方式
- 事件处理函数的命名（handleXxx / onXxx）
- 数据结构和 TypeScript 类型的位置

**你的新组件 = 参照组件的骨架 + 新功能的逻辑。**

---

## Phase 2: 写代码

### 规则：和参照组件保持一致

```
import 顺序          → 和参照一样
hooks 顺序           → 和参照一样（state → effect → callbacks → render）
样式写法             → 和参照一样（同样的 Tailwind class 组合 / CSS 变量）
Loading 状态         → 和参照一样的 Skeleton / Spinner
空数据状态           → 和参照一样的空状态 UI
错误处理             → 和参照一样的 catch + toast / 内联提示
组件导出             → 和参照一样的 export 方式
```

### 决不做的事
```
❌ 引入项目里没有的 UI 库（项目没有 antd 你不要突然 import antd）
❌ 换状态管理方式（项目用 Zustand 你不要突然用 Context API）
❌ 换样式方案（项目用 Tailwind 你不要写 styled-components）
❌ 换 API 调用方式（项目有封装好的 client 你不要直接 fetch）
❌ 加新颜色（用项目已有的 CSS 变量 / 主题色）
❌ 改变间距节奏（项目用 p-4/gap-4 你不要突然用 p-5/gap-3）
```

### 交互标准
```
每个用户操作都要有视觉反馈：
  按钮点击 → disabled + spinner（和项目已有按钮一样的 loading 态）
  表单提交 → 按钮 loading → 成功 toast / 失败 toast
  删除操作 → 确认弹窗（用项目已有的 Modal 组件）
  列表加载 → Skeleton / Loading（和其他列表页一致）
  切换 Tab → 新 tab 立即高亮（数据异步加载，UI 先切换）
```

---

## Phase 3: 集成检查

新功能写完后，逐项检查：

```
□ 路由注册了吗？（App.tsx / router 配置，格式和其他路由一致）
□ 导航入口加了吗？（Navbar / Sidebar / Menu，位置和风格和其他入口一致）
□ 权限检查和其他页面一致吗？（admin → admin check，user → login check）
□ 页面之间切换时数据/状态不冲突吗？
□ Loading/Error/Empty 三种状态都有吗？且和其他页面风格一致？
□ 移动端能正常显示吗？（和项目已有的响应式方案一致）
□ 深色/浅色主题正确吗？（如果项目有主题切换）
□ 浏览器后退/前进行为正常吗？
```

### 视觉一致性核对

```
□ 颜色 — 只用 CSS 变量 / 主题色，不加新颜色
□ 间距 — 和最近的参照页面完全一致
□ 圆角 — 和现有卡片/按钮的圆角一致
□ 阴影 — 和现有组件的阴影深度一致
□ 字号 — 标题/正文/标签的层级和其他页面一致
□ 动画 — 过渡效果类型和时长和其他组件一致
□ 图标 — 用项目已有的图标库和大小
```
