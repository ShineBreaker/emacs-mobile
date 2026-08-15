;;; init-touch.el --- 触屏交互：双组 tool-bar（命令/编辑）切换 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 方案 D''（真机迭代结论）：
;; · tool-bar 常显底部，内容在「命令组」与「编辑组」间切换，
;;   mode-line 右端状态块（tap）切换。
;; · modifier-bar 上游固定渲染、尺寸不可配且真机过小，弃用；
;;   编辑组的修饰键按钮用内置 `event-apply-*-modifier' 实现
;;   （点击后下一个输入事件自动带修饰符，行为与 modifier-bar 一致）。
;; · label 置空：Android 工具栏按钮会按 label 文本宽度（随字体放大）
;;   撑宽按钮，置空后宽度回到图标主导，保证单行。
;; 图标：Maple Mono NF CN 的 Nerd 字形渲染的 56px PNG（data/icons/，
;; `just icons` 重建）。

;;; Code:

;; ─── 图标路径（必须在下方 defconst 求值前就位：find-image 即时解析） ──

(add-to-list 'image-load-path
             (expand-file-name "data/icons" user-emacs-directory))

;; ─── tool-bar 按钮构造（跨平台定义，仅 Android 使用） ──────────────

(declare-function event-apply-control-modifier "subr")
(declare-function event-apply-meta-modifier "subr")
(declare-function event-apply-shift-modifier "subr")

(defun custom/touch--add-button (map key command help icon)
  "向 MAP 添加按钮：KEY 触发 COMMAND，图标 data/icons/ICON.png。
label 置空（理由见文件头）。"
  (define-key map (vector key)
    `(menu-item "" ,command
                :help ,help
                :image ,(find-image
                         `((:type png :file ,(concat icon ".png")))))))

(defun custom/touch--make-bar (buttons)
  "由 BUTTONS 构造 tool-bar keymap；每项 (key command help icon)。"
  (let ((map (make-sparse-keymap)))
    (dolist (b buttons map)
      (pcase-let ((`(,key ,command ,help ,icon) b))
        (custom/touch--add-button map key command help icon)))))

(defconst custom/touch--command-bar
  (custom/touch--make-bar
   '((save save-buffer "保存 (C-x C-s)" "save")
     (undo undo "撤销" "undo")
     (redo undo-redo "重做" "redo")
     ;; Org 组：命令由 init-org.el 提供，点击时才解析符号
     (capture org-capture "快速捕获" "capture")
     (agenda org-agenda "议程" "agenda")
     (roam org-roam-node-find "查找/新建 Roam 笔记" "roam")
     ;; 导航组
     (buffer consult-buffer "切换缓冲区" "buffer")
     (search custom/touch-search "搜索（rg 或当前缓冲区）" "search")
     ;; 视图组
     (recenter recenter-top-bottom "当前行回中" "recenter")
     ;; 切换到编辑组（主入口在工具栏内，mode-line 状态块为辅）
     (switch-kbd custom/touch-toggle-input-bar "切换到编辑组（修饰键/编辑键）"
                 "switch-kbd")))
  "命令组工具栏：高频命令直达。")

(defconst custom/touch--edit-bar
  (custom/touch--make-bar
   '((c event-apply-control-modifier "下一个输入加 Ctrl" "mod-c")
     (m event-apply-meta-modifier "下一个输入加 Meta" "mod-m")
     (s event-apply-shift-modifier "下一个输入加 Shift" "mod-s")
     (tab indent-for-tab-command "缩进/补全 (Tab)" "tab")
     (ret newline "换行 (RET)" "ret")
     (esc keyboard-quit "取消 (ESC)" "esc")
     (left backward-char "左移一字符" "arrow-left")
     (up previous-line "上一行" "arrow-up")
     (down next-line "下一行" "arrow-down")
     (right forward-char "右移一字符" "arrow-right")
     ;; 切回命令组
     (switch-cmd custom/touch-toggle-input-bar "切回命令组" "switch-cmd")))
  "编辑组工具栏：修饰键 + 编辑键，替代 modifier-bar。")

;; ─── 两组切换（跨平台） ─────────────────────────────────────────────

(defvar custom/touch--edit-bar-active nil
  "当前 tool-bar 是否显示编辑组。mode-line 状态块读取此变量。")

(defun custom/touch-toggle-input-bar ()
  "在命令组与编辑组工具栏间切换。"
  (interactive)
  (setq custom/touch--edit-bar-active (not custom/touch--edit-bar-active)
        tool-bar-map (if custom/touch--edit-bar-active
                         custom/touch--edit-bar
                       custom/touch--command-bar))
  (message "工具栏：%s" (if custom/touch--edit-bar-active "编辑组" "命令组"))
  (force-window-update (selected-frame)))

;; 搜索入口：rg 可用走 consult-ripgrep，缺失降级 consult-line
(declare-function consult-ripgrep "consult")
(declare-function consult-line "consult")
(defun custom/touch-search ()
  "搜索。rg 可用时全文检索，否则检索当前缓冲区。"
  (interactive)
  (if (executable-find "rg")
      (call-interactively #'consult-ripgrep)
    (call-interactively #'consult-line)))

;; ─── Android 触屏特化 ───────────────────────────────────────────────

(when custom:android-p
  ;; 底部 tool-bar（拇指可达）。Emacs 30.2 Android 的正确入口是
  ;; frame parameter（bug#64174），全局变量 setq 无效；三处同设覆盖
  ;; 当前 frame 与后续新建 frame，兼容 31+ 的 defcustom 形式。
  (setq tool-bar-position 'bottom)
  (set-frame-parameter nil 'tool-bar-position 'bottom)
  (add-to-list 'default-frame-alist '(tool-bar-position . bottom))

  ;; 按钮过小是 Android 版已知缺陷（margins 不随屏幕密度缩放），
  ;; 用边距放大触控面积；真机实测后在此调整数值。
  (setq tool-bar-button-margin 8)

  ;; 触屏选项：tap 任意处可唤出系统虚拟键盘
  (setq touch-screen-display-keyboard t
        touch-screen-preview-select t
        touch-screen-word-select t
        touch-screen-extend-selection t)

  ;; 触屏无菜单交互场景，关闭菜单栏省一行（命令走 tool-bar / M-x）
  (menu-bar-mode -1)

  ;; 初始态：命令组（image-load-path 已在文件顶部就位）
  (setq tool-bar-map custom/touch--command-bar)
  (tool-bar-mode 1)
  ;; modifier-bar 弃用（尺寸不可配、真机过小），确保关闭
  (when (fboundp 'modifier-bar-mode)
    (modifier-bar-mode -1)))

;; 桌面：无需工具栏
(unless custom:android-p
  (tool-bar-mode -1))

(provide 'init-touch)
;;; init-touch.el ends here
