;;; init-touch.el --- 触屏层：官方 modifier-bar + 触屏编辑命令 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 2026-08-15 方案 F 拍板：交互组件全部回归官方宿主——
;; · 修饰键 → 官方 modifier-bar（tap 后下一个输入带修饰；自实现的
;;   tap 一次性 + 锁定 + key-translation 全套删除）
;; · 全局命令按钮 → 官方 tool-bar（init-bar.el 安装，底部）
;; · buffer/窗口控制 → mode-line（init-ui.el）
;; 自实现 side window bar（方案 E）废弃根因：tap 会把 bar 的 window
;; 选中，复制/剪切/撤销/切缓冲区等命令全部落到 *mobile-bar* 自身。

;;; Code:

(declare-function dashboard-open "dashboard")

;; ─── 复制 / 剪切：有选区作用于选区，无选区作用于当前行 ─────────────
;; 触屏长按拖选产生 region（真机实测），无选区时整行操作更符合触屏直觉。

(defun custom/touch-copy ()
  "复制：有选区复制选区，否则复制当前行。"
  (interactive)
  (let* ((regionp (use-region-p))
         (beg (if regionp (region-beginning) (line-beginning-position)))
         (end (if regionp (region-end) (line-end-position))))
    (copy-region-as-kill beg end)
    (message "已复制%s" (if regionp "选区" "当前行"))))

(defun custom/touch-cut ()
  "剪切：有选区剪切选区，否则剪切当前行（连换行整行消失）。"
  (interactive)
  (let* ((regionp (use-region-p))
         (beg (if regionp (region-beginning) (line-beginning-position)))
         (end (if regionp (region-end) (progn (forward-line 1) (point)))))
    (kill-region beg end)
    (message "已剪切%s" (if regionp "选区" "当前行"))))

;; 搜索入口：rg 可用走 consult-ripgrep，缺失降级 consult-line
(declare-function consult-ripgrep "consult")
(declare-function consult-line "consult")
(defun custom/touch-search ()
  "搜索。rg 可用时全文检索，否则检索当前缓冲区。"
  (interactive)
  (if (executable-find "rg")
      (call-interactively #'consult-ripgrep)
    (call-interactively #'consult-line)))

;; ─── modifier-bar 开关 / 打开配置（tool-bar 首尾按钮的命令） ────────

(defun custom/touch-toggle-modifier-bar ()
  "显示/隐藏官方修饰键栏。"
  (interactive)
  (if (fboundp 'modifier-bar-mode)
      (modifier-bar-mode 'toggle)
    (message "本 Emacs 无 modifier-bar（需 Android 官方构建）")))

(defun custom/touch-open-config ()
  "打开配置入口 init.el。"
  (interactive)
  (find-file (expand-file-name "init.el" user-emacs-directory)))

;; ─── Android 触屏特化 ───────────────────────────────────────────────

(when custom:android-p
  ;; 触屏选项：tap 任意处可唤出系统虚拟键盘
  (setq touch-screen-display-keyboard t
        touch-screen-preview-select t
        touch-screen-word-select t
        touch-screen-extend-selection t)

  ;; 触屏无菜单交互场景，关闭菜单栏省一行（命令走 tool-bar / M-x）
  (menu-bar-mode -1)

  ;; 修饰键交官方 modifier-bar，默认开（tool-bar 首位按钮可开关）
  (when (fboundp 'modifier-bar-mode)
    (modifier-bar-mode 1)))

(provide 'init-touch)
;;; init-touch.el ends here
