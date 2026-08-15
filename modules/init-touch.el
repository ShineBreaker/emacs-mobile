;;; init-touch.el --- 触屏选项与修饰键命令 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 工具栏本体在 init-bar.el（底部 side window 字符按钮行，方案 E）；
;; 本模块只保留 touch-screen-* 选项与编辑组的修饰键命令。

;;; Code:

;; ─── 修饰键：按住式（hold）+ tap 一次性兜底 ────────────────────────
;; 交互：按住 C/M/S 按钮期间，键盘字母经 `key-translation-map' 带修饰
;; 派发（如按住 C 连敲 a e = C-a C-e 连击）；抬起解除。快速 tap（期间
;; 无输入）退化为一次性等待（read-event + 修饰派发）。
;; 能力边界（机制实测）：key-translation 只匹配按键序列开头——
;; C-x 前缀后的字母不会被翻译，故 C-x C-s 一类前缀式双修饰组合
;; 不走修饰按钮（触屏用 [存] 等按钮或 M-x 直达）。

(defvar custom/touch--hold-mod nil
  "按住中的修饰符（\\='control / \\='meta / \\='shift），nil 表示未按住。")
(defvar custom/touch--mod-consumed nil
  "本次按住期间是否已有键盘输入被翻译。")

(defun custom/touch--translate (prefix key-str)
  "返回翻译函数（单参 PROMPT，key-translation-map 调用约定）：
将 KEY-STR 翻译为带 PREFIX 修饰的键并标记 consumed。"
  (lambda (_prompt)
    (setq custom/touch--mod-consumed t)
    (kbd (concat prefix key-str))))

(defun custom/touch--hold-chars ()
  "参与翻译的字符列表（小写字母 + 数字）。"
  (append "abcdefghijklmnopqrstuvwxyz0123456789" nil))

(defun custom/touch--hold-start (mod prefix name)
  "按钮按下：安装字符翻译，修饰生效。"
  (setq custom/touch--hold-mod mod
        custom/touch--mod-consumed nil)
  (dolist (c (custom/touch--hold-chars))
    (let ((key-str (char-to-string c)))
      (define-key key-translation-map key-str
        (custom/touch--translate prefix key-str))))
  (message "%s- 按住中…" name))

(defun custom/touch--hold-clear ()
  "移除字符翻译。"
  (dolist (c (custom/touch--hold-chars))
    (define-key key-translation-map (char-to-string c) nil)))

(defun custom/touch--button-up ()
  "按钮抬起：解除修饰；期间无输入（纯 tap）则转一次性等待。"
  (interactive)
  (let ((mod custom/touch--hold-mod)
        (consumed custom/touch--mod-consumed))
    (custom/touch--hold-clear)
    (setq custom/touch--hold-mod nil)
    (cond
     ((not mod) nil)                        ; 非修饰按钮的抬起，无操作
     (consumed (message "修饰结束"))
     ;; tap 兜底：一次性修饰（event-apply 语义见下）
     (t (custom/touch--one-shot mod)))))

;; 一次性修饰（tap 兜底路径）。event-apply-*-modifier 官方语义
;; （实验确认）：丢弃参数、内部阻塞读下一个输入、返回修饰后事件的
;; vector（key sequence，为 keymap 绑定设计）。按钮场景返回值被
;; command-execute 丢弃，故取首元素作为单事件放回派发。
(declare-function event-apply-control-modifier "subr")
(declare-function event-apply-meta-modifier "subr")
(declare-function event-apply-shift-modifier "subr")

(defun custom/touch--one-shot (mod)
  "读取下一个输入，加修饰符 MOD 后作为单事件派发。"
  (let ((fn (pcase mod
              ('control #'event-apply-control-modifier)
              ('meta #'event-apply-meta-modifier)
              ('shift #'event-apply-shift-modifier))))
    (message "%s- 等待输入…" (upcase (symbol-name mod)))
    ;; 清掉 tap 残留的鼠标事件，避免被当作修饰目标
    (setq unread-command-events nil)
    (let ((modified (funcall fn last-input-event)))
      (when (and (vectorp modified) (> (length modified) 0))
        (push (aref modified 0) unread-command-events)))))

(defun custom/touch-ctrl-modifier ()
  "按住：键盘输入带 Ctrl；快速点按则下一个输入带 Ctrl。"
  (interactive)
  (custom/touch--hold-start 'control "C-" "C"))

(defun custom/touch-meta-modifier ()
  "按住：键盘输入带 Meta；快速点按则下一个输入带 Meta。"
  (interactive)
  (custom/touch--hold-start 'meta "M-" "M"))

(defun custom/touch-shift-modifier ()
  "按住：键盘输入带 Shift；快速点按则下一个输入带 Shift。"
  (interactive)
  (custom/touch--hold-start 'shift "S-" "S"))

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
