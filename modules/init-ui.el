;;; init-ui.el --- 主题（简化版深浅色）+ mode-line + 去 frame 标题 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 从桌面移植的简化版：
;; · ef-themes + light/dark 状态文件持久化
;; · mode-line 极简档 + 右端 [⇄] 底部栏切换开关
;; · 去 frame 标题（信息由 mode-line 承担）

;;; Code:

;; ─── 主字体：Maple Mono NF CN（中英等宽 + Nerd 图标字形） ──────────
;; Android 装到 Emacs home 的 fonts/（sfnt-android 枚举），桌面走
;; fontconfig；未装时 find-font 返回 nil，自动跳过。
;; 字号加大可同步放大 modifier-bar 按钮（其尺寸随 frame 字体）。
(defcustom custom/default-font-height 160
  "默认字号（1/10 pt）。加大可同步放大 modifier-bar 按钮。"
  :type 'integer
  :group 'emacs-mobile)

(let ((spec (font-spec :family "Maple Mono NF CN")))
  (when (and (display-graphic-p) (find-font spec))
    (set-face-attribute 'default nil :font spec
                        :height custom/default-font-height)))

;; ─── 主题：ef-themes + 简化深浅色状态机 ─────────────────────────────

(defcustom custom/color-scheme-light-theme 'ef-cyprus
  "浅色模式下加载的主题。"
  :type 'symbol
  :group 'emacs-mobile)

(defcustom custom/color-scheme-dark-theme 'ef-owl
  "深色模式下加载的主题。"
  :type 'symbol
  :group 'emacs-mobile)

(defcustom custom/color-scheme-default-mode 'light
  "无状态文件时的默认深浅色模式。"
  :type '(choice (const :tag "浅色" light)
                 (const :tag "深色" dark))
  :group 'emacs-mobile)

(defconst custom/color-scheme-state-file
  (expand-file-name "color-scheme-state.el" custom:var-directory)
  "颜色方案状态文件路径（目录由 init-basis 定义）。")

(defvar custom/color-scheme-current-mode nil
  "当前颜色方案模式（\='light 或 \='dark）。")

(defun custom/color-scheme-read-state ()
  "从状态文件读取当前模式，返回 \='light 或 \='dark，不可用时返回 nil。
读侧与 `custom/color-scheme-save-state' 的写入格式对称：read 解析
`(setq ...)' 表单，精确取第二元素，不做子串匹配。"
  (condition-case err
      (when (file-exists-p custom/color-scheme-state-file)
        (let ((form (with-temp-buffer
                      (insert-file-contents custom/color-scheme-state-file)
                      (goto-char (point-min))
                      (read (current-buffer)))))
          (pcase form
            (`(setq custom/color-scheme-current-mode (quote ,mode)) mode)
            (_ nil))))
    (error
     (message "[color-scheme] 无法读取状态文件: %s" (error-message-string err))
     nil)))

(defun custom/color-scheme-save-state (mode)
  "将当前模式 MODE 持久化到状态文件。"
  (condition-case err
      (let ((dir (file-name-directory custom/color-scheme-state-file)))
        (unless (file-exists-p dir)
          (make-directory dir t))
        (with-temp-buffer
          (insert ";; color-scheme-state.el -*- lexical-binding: t; -*-\n")
          (insert ";; 自动生成，勿手动修改\n")
          (insert (format "(setq custom/color-scheme-current-mode '%s)\n" mode))
          (write-region (point-min) (point-max) custom/color-scheme-state-file)))
    (error
     (message "[color-scheme] 无法保存状态文件: %s" (error-message-string err))
     nil)))

(defun custom/color-scheme-apply-theme (mode)
  "加载 MODE（\='light 或 \='dark）对应的主题并持久化状态
（用内置 `load-theme'，ef-themes 仅提供主题定义文件）。"
  (setq custom/color-scheme-current-mode mode)
  (custom/color-scheme-save-state mode)
  (let ((theme (pcase mode
                 ('light custom/color-scheme-light-theme)
                 ('dark custom/color-scheme-dark-theme))))
    (when (and theme (not (memq theme custom-enabled-themes)))
      ;; custom-theme-p 不适用：ef-themes 加载后所有主题名都被注册
      (mapc #'disable-theme custom-enabled-themes)
      (load-theme theme t))))

(defun custom/color-scheme-toggle ()
  "在浅色/深色主题间切换。"
  (interactive)
  (custom/color-scheme-apply-theme
   (if (eq custom/color-scheme-current-mode 'light) 'dark 'light)))

(defun custom/color-scheme-init ()
  "初始化：读状态文件 → 无则取默认 → 应用主题。"
  (custom/color-scheme-apply-theme
   (or (custom/color-scheme-read-state)
       custom/color-scheme-default-mode)))

(use-package ef-themes
  :defer t
  :init
  ;; 主题加载放启动完成后，避免拖慢 init
  (add-hook 'after-init-hook #'custom/color-scheme-init))

;; ─── frame 标题：去除（信息由 mode-line 承担） ─────────────────────

(setq frame-title-format '(""))

;; ─── mode-line：极简档 ─────────────────────────────────────────────

;; 触屏无新手引导，抑制启动屏
(setq inhibit-startup-screen t)

;; echo area 按需伸缩，避免底部空行残留
(setq resize-mini-windows 'grow-and-shrink)

(defun custom/mode-line--percent ()
  "当前位置百分比（%p/%P 在顶底部会显示 Top/Bottom/All）。"
  (format "%d%%%%"
          (floor (* 100.0 (point)) (max (point-max) 1))))

;; 行首放关闭当前 buffer 按钮（tap=mouse-1，与工具栏同机制）。
;; 缓冲区切换也放 mode-line：点击时所属窗口被选中，目标窗口正确。
(declare-function consult-buffer "consult")

(defun custom/mode-line-switch-buffer ()
  "在当前窗口切换缓冲区。"
  (interactive)
  (consult-buffer))

(declare-function custom/which-key-next-page "init-completion")
(declare-function custom/glyph "init-basis")
(declare-function consult-org-heading "consult")
(declare-function consult-imenu "consult")
(declare-function consult-line "consult")

(defun custom/mode-line-navigate ()
  "当前文档内导航：org 大纲 / epub 章节 / 其余本页搜索。"
  (interactive)
  (cond
   ((derived-mode-p 'org-mode) (consult-org-heading))
   ((derived-mode-p 'nov-mode) (consult-imenu))
   (t (consult-line))))

;; ─── 右端按钮组：数据表驱动 ────────────────────────────────────────
;; 对齐偏移须按真实字形宽自算：官方 `mode-line-format-right-align' 以
;; string-width 计右组宽，NF 私用区字形记 1 列但 Maple 实渲 2 列，
;; 组整体溢出右缘（× 钮出界不可点）。GUI NF 按 2 列计，tty 回退
;; 字符无歧义按 string-width。

(defconst custom/mode-line--right-buttons
  '(("\uF002" "寻" "文档内导航（org 大纲 / epub 章节 / 本页搜索）"
     custom/mode-line-navigate)
    ("\uF037" "中" "当前行回中" recenter-top-bottom)
    ("\uF0A9" "»" "which-key 下一页" custom/which-key-next-page)
    ("\uF0EC" "换" "切换缓冲区" custom/mode-line-switch-buffer)
    ("\uF00D" "×" "关闭当前 buffer 及其窗口" kill-buffer-and-window))
  "右端按钮表：(NF 字形 tty 回退 帮助 命令)，从左到右。")

(defun custom/mode-line--button (spec)
  "按 SPEC（字形 回退 帮助 命令）构造单颗按钮。"
  (pcase-let ((`(,glyph ,fallback ,help ,command) spec))
    (propertize
     (format " %s" (custom/glyph glyph fallback))
     'local-map (make-mode-line-mouse-map 'mouse-1 command)
     'mouse-face 'highlight
     'help-echo help)))

(defun custom/mode-line--buttons ()
  "右端按钮组串。"
  (mapconcat #'custom/mode-line--button custom/mode-line--right-buttons nil))

(defun custom/mode-line--mode-name ()
  "mode-name，超 12 列截断（窄屏防挤出右端按钮）。"
  (truncate-string-to-width (format-mode-line mode-name)
                            12 nil nil "…"))

(defun custom/mode-line-debug ()
  "弹出 mode-line 排版诊断（窗宽/列宽/字形像素），真机排障取证。"
  (interactive)
  (let ((buf (get-buffer-create "*mode-line 诊断*")))
    (with-current-buffer buf
      (fundamental-mode)
      (erase-buffer)
      (insert
       (format
        "window: %d 列 / %d px   frame-char-width: %d px\n\
string-pixel-width: a=%d 中=%d ·=%d ●=%d F002=%d F00D=%d\n\
string-width: F002=%S F00D=%S ·=%S ●=%S\n\
fringe: %S  scrollbar: %S\n\
右组串: %S\n\
右组串宽(列): %S\n\
mode-line 渲染串宽(列): %S"
        (window-total-width) (window-pixel-width) (frame-char-width)
        (string-pixel-width "a") (string-pixel-width "中")
        (string-pixel-width "·") (string-pixel-width "●")
        (string-pixel-width "\uF002") (string-pixel-width "\uF00D")
        (string-width "\uF002") (string-width "\uF00D")
        (string-width "·") (string-width "●")
        (fringe-columns 'right) (window-scroll-bar-columns)
        (custom/mode-line--buttons)
        (string-width (custom/mode-line--buttons))
        (string-width (format-mode-line mode-line-format))))
      (goto-char (point-min)))
    (pop-to-buffer buf)))

;; 左段：修改标记 mode-name 百分比；右端按钮组从左到右：
;; 寻 导航、中 回中、» 翻页、换 切缓冲区、× 关闭。
;; `mode-line-format-right-align' 须裸符号（format-mode-line 按变量
;; 处理）；NF 字形宽度已由 init-basis 的 char-width-table 置 2，对齐
;; 计量与实渲一致。
(setq-default mode-line-format
              '("%e"
                (:eval (if (buffer-modified-p) "●" "·"))
                " "
                (:eval (custom/mode-line--mode-name))
                "  "
                (:eval (custom/mode-line--percent))
                mode-line-format-right-align
                (:eval (custom/mode-line--buttons))))

;; ─── 编辑行为（自桌面配置移植）───────────────────────────────────────
;; CJK 按字符类别折行（Emacs 29+ 内置）：中文段落无空格断点也能正常折行
(setq word-wrap-by-category t)
;; 有选区时输入/粘贴覆盖选区，触屏拖选后直接打字
(delete-selection-mode 1)
;; 自动配对括号/引号 + 匹配括号高亮
(electric-pair-mode 1)
(show-paren-mode 1)
;; 长文档滚动更跟手（精确滚动在触屏上无感知收益）
(setq fast-but-imprecise-scrolling t)
;; org 目录在 Syncthing 共享存储上：.# 锁文件与 #file# auto-save 文件会
;; 被同步成各端垃圾；丢数据风险由失焦自动保存兜底（见下）
(setq create-lockfiles nil
      auto-save-default nil)

;; ─── 换行与行号：任何 buffer 软换行 + 编辑区小号行号 ──────────────

(global-visual-line-mode 1)

;; 行号只加在编辑类 buffer（prog/text/org）
(dolist (hook '(prog-mode-hook text-mode-hook org-mode-hook))
  (add-hook hook #'display-line-numbers-mode))
(setq-default display-line-numbers-width 2) ; 定宽 2 位，行号窄不挤
(set-face-attribute 'line-number nil :height 0.8)
(set-face-attribute 'line-number-current-line nil :height 0.8)

;; ─── 失焦自动保存（自桌面配置移植）：防 Android 后台被杀丢数据 ──────
;; 失去焦点后空闲 1s 保存所有已修改的本地文件 buffer，不保存远程与
;; 内部 buffer。`after-focus-change-function' 在 Android 端口的触发
;; 待真机确认；不触发则该机制不生效，无副作用。

(defconst custom:focus-save-idle-delay 1
  "失焦后保存用户文件 buffer 前等待的空闲秒数。")

(defvar custom--focus-save-timer nil
  "失焦保存的 pending idle timer。")

(defun custom/user-file-buffer-p ()
  "当前 buffer 是否为可保存的本地用户文件 buffer。"
  (and buffer-file-name
       buffer-file-truename
       (buffer-modified-p)
       (not buffer-read-only)
       (not (buffer-base-buffer))
       (not (file-remote-p buffer-file-name))))

(defun custom/recentf-save ()
  "持久化 recentf 列表（Android 后台被杀时 kill-emacs-hook 不执行）。"
  (when (and (bound-and-true-p recentf-mode) (fboundp 'recentf-save-list))
    (recentf-save-list)))

(defun custom/save-user-file-buffers ()
  "保存已修改的本地文件 buffer，并持久化 recentf 列表。"
  (setq custom--focus-save-timer nil)
  (save-some-buffers t #'custom/user-file-buffer-p)
  (custom/recentf-save))

(defun custom/save-buffer-and-recentf ()
  "保存当前 buffer 并持久化 recentf 列表（tool-bar 保存按钮用）。"
  (interactive)
  (save-buffer)
  (custom/recentf-save))

(defun custom/schedule-focus-save ()
  "按焦点状态安排或取消空闲保存（有 frame 聚焦时不保存）。"
  (when (timerp custom--focus-save-timer)
    (cancel-timer custom--focus-save-timer)
    (setq custom--focus-save-timer nil))
  (unless (seq-some #'frame-focus-state (frame-list))
    (setq custom--focus-save-timer
          (run-with-idle-timer custom:focus-save-idle-delay nil
                               #'custom/save-user-file-buffers))))

(add-function :after after-focus-change-function #'custom/schedule-focus-save)

(provide 'init-ui)
;;; init-ui.el ends here
