# CLAUDE.md

> **本文件会被 commit 到 public fork**，因此**不得包含任何敏感信息**（个人路径、真实邮箱、手机号、Lark ID、token 等）。
>
> 如果当前工作目录存在 `CLAUDE.local.md`（已 gitignore），请同时阅读它 —— 那里存放本机私有上下文（具体扫描脚本路径、私有备忘等），不会进 git。

## 项目概述

这是 [mermaid-js/mermaid-live-editor](https://github.com/mermaid-js/mermaid-live-editor) 的本地部署，在其基础上添加了两个自定义脚本工具。

- 开源库本身：SvelteKit 应用，提供 mermaid 图表的实时编辑和预览
- 自定义部分：`mmd-open.sh`、`mmd-dashboard.sh`、`mmd-serve.sh`，用于快速打开本地 `.mmd` 文件和启动 live editor

**重要原则：所有本地改动尽量以「加法」形式存在（新增文件），避免修改上游源文件**，这样官方更新时 merge 冲突最小。端口偏好等配置通过包装脚本（如 `mmd-serve.sh` 传 `--port`）覆盖，而不是改 `vite.config.js`。

## 自定义脚本

### mmd-open.sh

打开单个 `.mmd` 文件到 live editor 进行编辑。

```bash
mmd-open path/to/diagram.mmd        # 默认端口 4000
mmd-open path/to/diagram.mmd 5173   # 指定 live editor 端口
```

工作原理：读取文件内容 → 构造 State JSON → pako deflate + js-base64 编码 → 拼接 URL `localhost:4000/edit#pako:...` → `open` 打开浏览器。

注意：URL 必须指向 `/edit#pako:...` 路径，不能用根路径 `/#pako:...`，否则根路由的 redirect 逻辑会丢弃 hash 数据。

### mmd-dashboard.sh

生成一个看板页面，预览指定文件夹下所有 `.mmd` 文件，点击任意卡片跳转到 live editor 编辑。

```bash
mmd-dashboard                        # 当前目录，editor 端口 4000，看板端口 8787
mmd-dashboard ~/my-diagrams          # 指定目录
mmd-dashboard ~/my-diagrams 4000 8787  # 指定 editor 端口和看板端口
```

关键设计决策：

- **使用本地 mermaid.js 渲染**（`node_modules/.pnpm/mermaid@11.14.0/...`），不走 CDN。实测本地 ~150ms vs CDN ~10s，快约 60 倍
- 需要一个本地 HTTP server（python3）来 serve 文件，因为浏览器 `file://` 协议不允许加载 ES module
- 每次运行会自动杀掉占用同一端口的旧进程，无需手动清理
- 扫描时跳过隐藏目录（如 `.Trash`），最大深度 2 层
- 没有做热更新机制：切换文件夹时重新运行命令即可，启动成本 <1 秒

### 注释提取为卡片描述

dashboard 会从 `.mmd` 文件中提取 `%%` 注释，显示在卡片底部作为文字描述。提取规则：

- 跳过 frontmatter `---...---` 块
- 收集紧随其后的连续 `%%` 注释行
- 遇到非注释、非空行时停止

### mmd-serve.sh

启动 live editor dev server，包装 `pnpm dev --` 并传 `--port`。

```bash
mmd-serve          # 默认端口 4000
mmd-serve 5173     # 指定端口
```

设计目的：保持 `vite.config.js` 零改动（源端口仍是 3000），通过 CLI flag 覆盖端口偏好，避免上游合并冲突。

### 全局别名

已在 `~/.zshrc` 中配置：

```bash
alias mmd-open="$HOME/Kit/mermaid-live-editor/mmd-open.sh"
alias mmd-dashboard="$HOME/Kit/mermaid-live-editor/mmd-dashboard.sh"
alias mmd-serve="$HOME/Kit/mermaid-live-editor/mmd-serve.sh"
```

## 启动 Live Editor

```bash
mmd-serve              # 本地惯用启动方式，端口 4000
# 等价于：cd ~/Kit/mermaid-live-editor && pnpm dev -- --port 4000
```

运行在 `localhost:4000`。`mmd-open` 和 `mmd-dashboard` 的点击跳转编辑功能依赖此服务。`mmd-dashboard` 会在检测到端口空闲时自动起这个服务。

## .mmd 文件编写规范

`%%` 注释是 mermaid 官方语法，所有渲染器都支持。但有一个关键约束：

**`%%` 注释必须放在 frontmatter `---` 块之后，不能放在之前。** Mermaid 要求 frontmatter 是文件的第一行内容。

正确写法：

```
---
config:
  layout: dagre
  theme: redux
---
%% 注释放这里
flowchart TD
    A --> B
```

错误写法（会导致 frontmatter 不被识别）：

```
%% 注释不能放在 frontmatter 之前
---
config:
  theme: redux
---
```

## 注意事项

- dashboard 预览渲染时会剥离 frontmatter 块，因为某些 theme（如 `redux`）不是 mermaid 内置主题，只有 live editor 支持
- 点击卡片跳转到 live editor 时传递的是完整原始代码（包括 frontmatter），live editor 能正确处理

---

## Git 仓库架构与工作流（重要）

> 本节适用于「我」（Claude）和「用户」双方。任何 git 操作前请先核对此节，避免误推、隐私泄漏或破坏上游同步通路。

### 双 remote 架构

```
origin     →  github.com/kvincc/mermaid-live-editor          (用户的 fork，public)
                fetch ✓ / push ✓  ——  日常推送目标
upstream   →  github.com/mermaid-js/mermaid-live-editor       (官方仓库)
                fetch ✓ / push ❌  ——  push URL 已被故意设为无效字符串
```

`develop` 分支配置：

- `branch.develop.remote = upstream` → `git pull` 拉官方
- `branch.develop.pushRemote = origin` → `git push` 推自己的 fork
- `branch.develop.merge = refs/heads/develop`

### ⚠️ 隐私与安全（本仓库 fork 是 public）

**这个 fork 在 GitHub 上是公开的**，意味着任何 commit、文件内容、commit message、commit 元信息都会被全网可见可索引。每次操作前的检查清单：

1. **commit 的文件内容不得包含**：
   - 个人路径（含本机用户名的绝对路径）—— 用 `$HOME` / `$SCRIPT_DIR` / `~` 替代
   - 真实邮箱、手机号、Lark open_id、昵称等个人识别信息
   - 任何 token / API key / 密码 / `.env` 内容
2. **commit 元信息（author email）已配为 noreply 别名**，不要切回真实邮箱。具体值请直接查 `git config user.email`，本文档不写出，避免被搜索引擎索引到 noreply ↔ GitHub 账号的映射（虽然 noreply 本身不会泄漏邮箱，但减少暴露面更稳）。
3. **新增文件前先扫一次**敏感模式（个人用户名、邮箱前缀、手机号、Lark ID 前缀 `ou_` 等）。可在本机维护一个 **gitignored 的扫描脚本**（含真实关键词）放在仓库外，比如 `~/.config/privacy-scan.sh`，由 Claude / 你手动调用，避免敏感模式本身被 commit。
4. **commit message 也是公开的**，不要在 message 里写内部代号、客户名、未公开的 idea。

### 日常工作流

#### 提交本地改动（最常见）

```bash
git status                      # 确认改动文件
git add <文件>                   # 不要用 git add . 或 -A，避免误传敏感文件
git commit -m "local: <说明>"    # 必须用 'local:' 前缀，便于和上游 commit 区分
git push                        # 自动推到 origin (你的 fork)
```

**commit message 约定**：所有本地改动统一用 `local:` 前缀（如 `local: add xxx`、`local: fix yyy`），方便日后用 `git log --oneline | grep '^[a-f0-9]* local:'` 一眼看出本地差异。

#### 从官方同步最新代码

```bash
git fetch upstream               # 拉取官方最新（不改本地代码）
git log HEAD..upstream/develop   # 看上游有哪些新 commit
git merge upstream/develop       # 合并；若有冲突手工解
git push                         # 把同步后的状态推到你的 fork
```

**冲突处理原则**：

- 上游改动优先采纳（除非和你的 `local:` 改动直接矛盾）
- 你的 `local:` 改动不能丢，必要时重新 apply
- 解完冲突后再做一次隐私扫描（防止 merge 把别处内容意外带入）

#### ❌ 禁止操作

| 操作                               | 后果                                    | 替代方案                                  |
| ---------------------------------- | --------------------------------------- | ----------------------------------------- |
| `git push upstream`                | 会失败（push URL 已锁），但永远不要尝试 | `git push`（推 fork）                     |
| `git push --force` 到 upstream     | 即使锁了也别试，毫无意义                | —                                         |
| 修改 `vite.config.js` 等上游源文件 | 每次 merge upstream 都会冲突            | 用包装脚本（如 `mmd-serve.sh`）+ CLI flag |
| `git add .` / `git add -A`         | 可能误带 `.env`、临时文件、其他敏感内容 | 显式列出文件名                            |
| 切回真实邮箱                       | commit log 永久暴露邮箱                 | 保持 noreply 别名                         |
| commit 不带 `local:` 前缀          | 难以和上游 commit 区分                  | 一律加前缀                                |

### Claude 自检清单（每次 git 操作前）

我（Claude）在执行任何 commit / push / remote 操作前，必须：

1. 跑 `git remote -v` 确认 origin / upstream 没被错改
2. 跑 `git config user.email` 确认仍是 noreply 邮箱
3. `git diff --cached` 扫一遍隐私敏感模式
4. push 前确认目标是 `origin`（fork）而非 `upstream`
5. 任何破坏性操作（`reset --hard`、`push --force`、删除分支、改 remote URL）**必须先问用户确认**，不得自作主张
