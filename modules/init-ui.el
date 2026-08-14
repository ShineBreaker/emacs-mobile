;;; init-ui.el --- 主题（简化版深浅色）+ mode-line + 去 frame 标题 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 从桌面移植的简化版：
;; · ef-themes + light/dark 状态文件持久化（删除 D-Bus/Darkman 机制，Android 无 D-Bus）
;; · mode-line 极简档 + 右端 [⇄] 底部栏切换开关（方案 D）
;; · 去 frame 标题（信息由 mode-line 承担）

;;; Code:

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
  "从状态文件读取当前模式，返回 \='light 或 \='dark，不可用时返回 nil。"
  (condition-case err
      (when (file-exists-p custom/color-scheme-state-file)
        (let ((content (with-temp-buffer
                         (insert-file-contents custom/color-scheme-state-file)
                         (buffer-string))))
          (cond
           ((string-match-p "dark" content) 'dark)
           ((string-match-p "light" content) 'light)
           (t nil))))
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
  "加载 MODE（\='light 或 \='dark）对应的主题并持久化状态。
用内置 `load-theme'（ef-themes 仅提供主题定义文件）。"
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
  ;; 主题加载放启动完成后，避免拖慢 init 并遵循 face 变体正确初始化
  (add-hook 'after-init-hook #'custom/color-scheme-init))

;; ─── frame 标题：去除（信息由 mode-line 承担） ─────────────────────

(setq frame-title-format '(""))

;; ─── mode-line：极简档 + 底部栏切换开关 ────────────────────────────

;; 切换块显示「点击后将切换到的目标态」：kbd = 修饰键盘，cmd = 命令面板。
;; 纯 ASCII：emoji/箭头符号在窄屏 tty 下宽度歧义导致溢出折行。
(defvar custom/mode-line--bar-switch-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line mouse-1] #'custom/touch-toggle-input-bar)
    map)
  "mode-line 右端切换块的点击 keymap（命令定义于 init-touch.el）。")

(defun custom/mode-line--bar-switch ()
  "返回底部栏切换指示块；触屏 tap（= mouse-1）切换 tool-bar/modifier-bar。"
  (propertize
   (if (bound-and-true-p modifier-bar-mode) "[cmd]" "[kbd]")
   'keymap custom/mode-line--bar-switch-map
   'mouse-face 'mode-line-highlight
   'help-echo "点击切换 命令栏 / 修饰键栏"))

;; 触屏场景无新手引导，抑制启动屏
(setq inhibit-startup-screen t)

(defun custom/mode-line--percent ()
  "当前位置百分比（自算：%p/%P 在顶底部会显示 Top/Bottom/All）。"
  (format "%d%%%%"
          (floor (* 100.0 (point)) (max (point-max) 1))))

;; 不用 mode-line-front-space：tty 下它渲染为 "-"。
;; 不用内置 mode-line-format-right-align：其列预算在 tty 下少算 1 列，
;; 尾部溢出折行；右端块定宽 5 列（[kbd]/[cmd]），自留 6 列预算。
(setq-default mode-line-format
              '("%e"
                " "
                (:eval (if (buffer-modified-p) "●" "·"))
                " " mode-name
                "  "
                (:eval (custom/mode-line--percent))
                (:eval (propertize " " 'display '(space :align-to (- right 6))))
                (:eval (custom/mode-line--bar-switch))))

(provide 'init-ui)
;;; init-ui.el ends here
