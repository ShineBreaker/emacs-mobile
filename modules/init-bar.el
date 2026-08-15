;;; init-bar.el --- 底部字符工具栏（side window + 专用 buffer） -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 方案 E（替代 tool-bar 与 mode-line 按钮行，2026-08-15 拍板）：
;; · 底部 side window 常驻一个 1 行高的专用 buffer，字符按钮直接渲染
;;   （GUI 用 Maple NF 字形，tty 用中文单字标签），tap = mouse-1 触发。
;; · 内容在命令组与编辑组间切换（切换按钮在行尾）。
;; · 该 buffer 隐藏 mode-line（mode-line-format nil）。
;; · 相比 tool-bar：无 PNG 管线、按钮跟字体大小、跟主题前景色（暗色
;;   主题下 PNG 黑色字形不可见的问题不复存在）、无渲染/派发双注册。

;;; Code:

(defconst custom/bar--buffer-name "*mobile-bar*"
  "工具栏 buffer 名。")

(defvar custom/bar--edit-bar-active nil
  "当前是否显示编辑组。")

(defcustom custom/bar-font-height 240
  "工具栏字号（1/10 pt），独立于内容字号——放大按钮触控面积
而不影响正文。真机试值调整。"
  :type 'integer
  :group 'emacs-mobile)

(define-derived-mode custom/bar-mode special-mode "Bar"
  "底部工具栏 buffer 模式。"
  (setq buffer-read-only t
        mode-line-format nil       ; 隐藏 mode-line，纯按钮行
        truncate-lines t           ; 溢出截断，保证单行
        show-trailing-whitespace nil))

;; 按钮规格：(GUI 字形 | tty 标签 | 命令 | help)。tty 无 NF 字形，用中文。
(defconst custom/bar--command-buttons
  '(("\uF0C7" "存" save-buffer "保存 (C-x C-s)")
    ("\uF0E2" "撤" undo "撤销")
    ("\uF01E" "重" undo-redo "重做")
    ("\uF0E7" "抓" org-capture "快速捕获")
    ("\uF133" "程" org-agenda "议程")
    ("\uF0C1" "笔" org-roam-node-find "查找/新建 Roam 笔记")
    ("\uF0EC" "换" consult-buffer "切换缓冲区")
    ("\uF002" "搜" custom/touch-search "搜索（rg 或当前缓冲区）")
    ("\uF037" "中" recenter-top-bottom "当前行回中")
    ("\uF11C" "⌨" custom/bar-toggle-group "切换到编辑组（修饰键/编辑键）"))
  "命令组按钮：高频命令直达。")

;; 修饰按钮 → 锁定模式下的修饰符（高亮判断用，见 custom/bar--face-for）
(defconst custom/bar--modifier-commands
  '((custom/touch-ctrl-modifier . control)
    (custom/touch-meta-modifier . meta)
    (custom/touch-shift-modifier . shift)))

(defvar custom/touch--lock-mode nil)      ; init-touch.el
(defvar custom/touch--locked-mods nil)    ; init-touch.el

(defconst custom/bar--edit-buttons
  '(("\uF023" "锁" custom/touch-lock-toggle
     "修饰锁定开关：开启后点 C/M/S 叠加锁定（可组合 C-M-），再点清除")
    ("C" "C" custom/touch-ctrl-modifier "下一个输入加 Ctrl")
    ("M" "M" custom/touch-meta-modifier "下一个输入加 Meta")
    ("S" "S" custom/touch-shift-modifier "下一个输入加 Shift")
    ("\u21E5" "Tab" indent-for-tab-command "缩进/补全")
    ("\uF138" "RET" newline "换行")
    ("ESC" "ESC" keyboard-quit "取消")
    ("\u2190" "←" backward-char "左移一字符")
    ("\u2191" "↑" previous-line "上一行")
    ("\u2193" "↓" next-line "下一行")
    ("\u2192" "→" forward-char "右移一字符")
    ("\uF0C9" "☰" custom/bar-toggle-group "切回命令组"))
  "编辑组按钮：锁定 + 修饰键 + 编辑键，替代 modifier-bar。")

(defun custom/bar--face-for (cmd)
  "按钮 CMD 的常规 face：锁定模式的锁钮与已锁修饰钮高亮。"
  (cond
   ((and (eq cmd 'custom/touch-lock-toggle) custom/touch--lock-mode)
    'highlight)
   ((and custom/touch--lock-mode
         (memq (cdr (assq cmd custom/bar--modifier-commands))
               custom/touch--locked-mods))
    'highlight)
   (t 'default)))

(defun custom/bar--render ()
  "把当前组的按钮渲染进工具栏 buffer。"
  (let ((gui (display-graphic-p))
        (buttons (if custom/bar--edit-bar-active
                     custom/bar--edit-buttons
                   custom/bar--command-buttons)))
    (with-current-buffer (get-buffer-create custom/bar--buffer-name)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (dolist (b buttons)
          (pcase-let ((`(,gui-glyph ,tty-glyph ,cmd ,help) b))
            (insert
             (propertize
              (format " %s " (if gui gui-glyph tty-glyph))
              'face (custom/bar--face-for cmd)
              'keymap (let ((m (make-sparse-keymap)))
                        (define-key m [mouse-1] cmd)
                        m)
              'mouse-face 'highlight
              'help-echo help))))
        (goto-char (point-min))))))

(defun custom/bar-toggle-group ()
  "在命令组与编辑组间切换。"
  (interactive)
  (setq custom/bar--edit-bar-active (not custom/bar--edit-bar-active))
  (custom/bar--render)
  (message "工具栏：%s" (if custom/bar--edit-bar-active "编辑组" "命令组")))

(defun custom/bar--setup ()
  "创建工具栏 buffer 并装入底部 side window（常驻、高度自适应）。"
  (custom/bar--render)
  (with-current-buffer (get-buffer custom/bar--buffer-name)
    (custom/bar-mode)
    ;; buffer 局部字号放大（独立于内容区），窗口行高随之增大
    (face-remap-add-relative 'default :height custom/bar-font-height))
  (condition-case err
      (let ((win (display-buffer-in-side-window
                  (get-buffer custom/bar--buffer-name)
                  '((side . bottom)
                    (window-height . fit-window-to-buffer)
                    (slot . 0)))))
        (set-window-parameter win 'no-other-window t)
        (set-window-parameter win 'no-delete-other-windows t)
        (fit-window-to-buffer win nil 1))
    (error
     (message "[mobile-bar] 安装失败: %s" (error-message-string err)))))

;; batch 无 frame 不安装；GUI 与 tty（tmux 排版校验）都显示。
;; 用 window-setup-hook（而非 after-init-hook）：它在初始 frame 窗口
;; 布局完成后触发，after-init 时布局未稳，side window 可能被重置。
(unless noninteractive
  (add-hook 'window-setup-hook #'custom/bar--setup))

(provide 'init-bar)
;;; init-bar.el ends here
