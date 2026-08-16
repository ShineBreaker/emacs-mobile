# AGENTS.md — emacs-mobile 项目约束

项目级指令，与用户默认指令（~/.zcode/AGENTS.md）叠加生效。本文件记录架构审查确立的约束与待办，改代码前先对照。

## 项目概览

Android 原生 Emacs 触屏配置（纯触屏、无键盘交互）＋ Termux APK 重签流水线。

- 入口：`early-init.el`（启动优化）→ `init.el`（require 序列即模块依赖契约，见约束 1）
- 模块：`modules/init-*.el`，basis / packages / ui / touch / bar / completion / org / dashboard / reading / misc
- `justfile`：本地命令包装（`just emacs` 一键补全依赖、`just termux` 重签、`just icons` 图标、`just clean` 清理）
- `data/icons/`：tool-bar 图标资产（SVG + PNG 兜底 + PBM 徽章，规格见约束 4）
- `docs/`：部署/签名机制文档，改签名链路前先读 `docs/00-workflow.md`
- 改部署链路前先读 README（含真机验证清单 §7）与 `data/icons/README.md`

## 架构约束

1. **加载顺序即契约** — init.el 的 require 序列是模块依赖的唯一契约，不得随意调换。跨模块引用必须显式声明：函数用 `declare-function`，变量用 `defvar` 在使用方就近声明；禁止用 `boundp` 防御访问他模块变量。
2. **图标加载唯一入口** — `custom/icon-asset`（init-basis）：SVG 主题重着色 / PBM 徽章 / PNG 兜底统一回退链。新增按钮/徽章图标一律走此入口，禁止另写 find-image 实现。
3. **字形降级唯一入口** — `custom/glyph`（init-basis）：GUI NF 字形 + tty 回退文字。新增字形禁止再写裸 `(if (display-graphic-p) ...)` 分支；`custom/dashboard--icon`（带 face、nil 契约）是 dashboard 视觉层封装，与 glyph 不同层，保留。
4. **徽章资产规格** — 字母 32×32、Tab/Esc 64×32。justfile `icons` 配方是唯一生成源，elisp 侧尺寸注释必须与其一致。
5. **颜色状态文件** — 写侧输出 elisp setq 表单，读侧 `read` 精确解析，读写对称；禁止子串匹配。
6. **org-roam 数据访问接口** — `custom/org-roam-recent-notes`（init-org）是展示层唯一入口：查询 + 错误降级集中于此；任何启动/查询路径不做全量同步（`org-roam-db-sync` 在 Android FUSE 存储上逐文件读全文算 hash，分钟级阻塞主线程；db 被残留 sqlite3 锁住时每条查询还要各等满 `emacsql-global-timeout`，故降额为 3s）。索引仅由保存时增量维护（`custom/org-roam-update-on-save`；不开 `org-roam-db-autosync-mode`，其开启时自带一次全量）；全量重建手动 `M-x org-roam-db-sync`。schema/版本变更只改 init-org；展示层禁止直接调 org-roam-db-* / require org-roam。

## 改动后验证

- 桌面验证一律以 `HOME=$(pwd)/.sandbox` 隔离，禁止污染真实配置；Android 特化代码在 `(when custom:android-p ...)` 守卫内，桌面加载自动跳过。
- 冒烟测试（跑完整 init）：
  ```sh
  HOME=$(pwd)/.sandbox emacs --batch \
    --eval "(setq user-emacs-directory \"$(pwd)/\")" \
    -l early-init.el -l init.el
  ```
- 单模块 byte-compile（须先加载完整配置，否则误报）：
  ```sh
  HOME=$(pwd)/.sandbox emacs --batch \
    --eval "(setq user-emacs-directory \"$(pwd)/\")" \
    -l early-init.el -l init.el \
    --eval '(byte-compile-file "modules/init-<模块>.el")'
  ```
- UI 改动流程：先出字符画/方案正文等作者拍板 → 用手机比例 tmux 窗口（40×80 ≈ 18:9）校验排版 → 交互改动做事件闭环验证。命令细节见 README 末尾。

## 当前状态

- C1（dashboard 拆层）、C2（图标管线）、C3（字形统一）、C4（声明显式化）、C5（颜色状态对称）均已落地。
- 遗留观察项：early-init/init.el 部署转发双份镜像判定未收敛（工作正常，改动敏感）；justfile/scripts 与 Elisp 层概念重复（图标清单、字体、apk 重签）待评估；straight 的 use-package 集成注入 `eval-when-compile (load "org-roam")`，从源码编译 init-org 时会加载 org-roam（autosync 已剥离，仅包加载本身，秒级）。
