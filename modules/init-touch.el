;;; init-touch.el --- 触屏选项与修饰键命令 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 工具栏本体在 init-bar.el（底部 side window 字符按钮行，方案 E）；
;; 本模块只保留 touch-screen-* 选项与编辑组的修饰键命令。

;;; Code:

;; ─── 修饰键命令（编辑组按钮调用） ──────────────────────────────────
;; event-apply-*-modifier 无 interactive 声明（设计给 keymap 绑定，
;; 如 C-x @ c），按钮点击走 command-execute 要求 commandp，须包装。

(declare-function event-apply-control-modifier "subr")
(declare-function event-apply-meta-modifier "subr")
(declare-function event-apply-shift-modifier "subr")

(defun custom/touch--apply-modifier (fn name)
  "读取下一个输入事件，经 FN 施加修饰符后派发。"
  (message "%s- 等待输入…" name)
  (let ((ev (read-event (concat name "-") t)))
    (when ev
      (push (funcall fn ev) unread-command-events))))

(defun custom/touch-ctrl-modifier ()
  "下一个输入事件加 Ctrl（等价按住 Ctrl）。"
  (interactive)
  (custom/touch--apply-modifier #'event-apply-control-modifier "C"))

(defun custom/touch-meta-modifier ()
  "下一个输入事件加 Meta（等价按住 Meta）。"
  (interactive)
  (custom/touch--apply-modifier #'event-apply-meta-modifier "M"))

(defun custom/touch-shift-modifier ()
  "下一个输入事件加 Shift（等价按住 Shift）。"
  (interactive)
  (custom/touch--apply-modifier #'event-apply-shift-modifier "S"))

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
  ;; 触屏选项：tap 任意处可唤出系统虚拟键盘
  (setq touch-screen-display-keyboard t
        touch-screen-preview-select t
        touch-screen-word-select t
        touch-screen-extend-selection t)

  ;; 触屏无菜单交互场景，关闭菜单栏省一行（命令走底部工具栏 / M-x）
  (menu-bar-mode -1)

  ;; modifier-bar 弃用（尺寸不可配、真机过小），确保关闭
  (when (fboundp 'modifier-bar-mode)
    (modifier-bar-mode -1)))

;; tool-bar 全平台关闭（工具栏由 init-bar 的 side window 承担）
(tool-bar-mode -1)

(provide 'init-touch)
;;; init-touch.el ends here
