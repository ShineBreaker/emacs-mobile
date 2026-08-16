# AGENTS.md — emacs-mobile 项目约束

项目级指令，与用户默认指令（~/.zcode/AGENTS.md）叠加生效。本文件记录架构审查确立的约束与待办，改代码前先对照。

## 架构约束

1. **加载顺序即契约** — init.el 的 require 序列是模块依赖的唯一契约，不得随意调换。跨模块引用必须显式声明：函数用 `declare-function`，变量用 `defvar` 在使用方就近声明；禁止用 `boundp` 防御访问他模块变量。
2. **图标加载唯一入口** — `custom/icon-asset`（init-basis）：SVG 主题重着色 / PBM 徽章 / PNG 兜底统一回退链。新增按钮/徽章图标一律走此入口，禁止另写 find-image 实现。
3. **字形降级唯一入口** — `custom/glyph`（init-basis）：GUI NF 字形 + tty 回退文字。新增字形禁止再写裸 `(if (display-graphic-p) ...)` 分支；dashboard 侧 5 处待迁移（改 dashboard 时顺手接）。
4. **徽章资产规格** — 字母 32×32、Tab/Esc 64×32。justfile `icons` 配方是唯一生成源，elisp 侧尺寸注释必须与其一致。
5. **颜色状态文件** — 写侧输出 elisp setq 表单，读侧 `read` 精确解析，读写对称；禁止子串匹配。
6. **org-roam 数据访问** — 查询 + 增量同步 + 错误降级应收进 init-org 模块（C1 待办）；dashboard 改完后再实施，当前 dashboard 内现有 SQL 保持不动。

## 当前状态

- dashboard 由作者并行修改中，改前必须重读 init-dashboard.el。
- C1（dashboard 拆层）未实施；C2/C3/C4 主体已落地（见提交历史）。
