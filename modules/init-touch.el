;;; init-touch.el --- 触屏选项与修饰键命令 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 工具栏本体在 init-bar.el（底部 side window 字符按钮行，方案 E）；
;; 本模块只保留 touch-screen-* 选项与编辑组的修饰键命令。

;;; Code:

;; ─── 修饰键：tap 一次性 ─────────────────────────────────────────────
;; 点按 C/M/S 后下一个输入带修饰（如点 C 再按 a = C-a）。
;; 真机实测否决的备选（勿再尝试，除非上游行为变化）：
;; · 按住式（mouse-1 down/up 事件对 + key-translation 字母翻译）——
;;   Android 触屏的 mouse-1 在抬手时才合成（down/up 紧邻到达，无
;;   「按住期间」），长按 0.7s 被系统拖选手势占用（触发 Mark set）。
;; · key-translation 也只匹配序列开头，C-x 前缀后的字母不翻译——
;;   C-x C-s 一类前缀式双修饰请用 [存] 等按钮或 M-x 直达。

(declare-function event-apply-control-modifier "subr")
(declare-function event-apply-meta-modifier "subr")
(declare-function event-apply-shift-modifier "subr")

(defun custom/touch--one-shot (fn name)
  "下一个输入经 FN 加修饰后作为单事件派发。
event-apply-*-modifier 官方语义（实验确认）：丢弃参数、内部阻塞读
下一个输入、返回修饰后事件的 vector（key sequence，为 keymap 绑定
设计）。按钮场景返回值被 command-execute 丢弃，故取首元素作为单
事件放回 `unread-command-events' 派发。"
  (message "%s- 等待输入…" name)
  ;; 清掉 tap 残留的鼠标事件（mouse-1-up 等），避免被当作修饰目标
  (setq unread-command-events nil)
  (let ((modified (funcall fn last-input-event)))
    (when (and (vectorp modified) (> (length modified) 0))
      (push (aref modified 0) unread-command-events))))

(defun custom/touch-ctrl-modifier ()
  "下一个输入事件加 Ctrl（点按按钮后再输入）。"
  (interactive)
  (custom/touch--one-shot #'event-apply-control-modifier "C"))

(defun custom/touch-meta-modifier ()
  "下一个输入事件加 Meta（点按按钮后再输入）。"
  (interactive)
  (custom/touch--one-shot #'event-apply-meta-modifier "M"))

(defun custom/touch-shift-modifier ()
  "下一个输入事件加 Shift（点按按钮后再输入）。"
  (interactive)
  (custom/touch--one-shot #'event-apply-shift-modifier "S"))

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
