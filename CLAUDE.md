# CLAUDE.md

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
