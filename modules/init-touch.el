;;; init-touch.el --- 触屏选项与修饰键命令 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 工具栏本体在 init-bar.el（底部 side window 字符按钮行，方案 E）；
;; 本模块只保留 touch-screen-* 选项与编辑组的修饰键命令。

;;; Code:

;; ─── 修饰键：tap 一次性 + 锁定模式（编辑组行首锁形按钮） ─────────
;; · tap 一次性（默认）：点 C/M/S 后下一个输入带修饰（点 C 按 a = C-a）。
;; · 锁定模式（编辑组行首锁形按钮开关）：开启后点 C/M/S 叠加锁定（可多选，
;;   如 C+M → 键盘输入带 C-M-），被锁按钮高亮；键盘字母经
;;   key-translation 常驻翻译。锁定集合在序列开头生效——单键双修饰
;;   组合（C-M-x）可达；C-x 前缀序列中间不翻译（机制边界）。
;; 真机实测否决的备选（勿再尝试，除非上游行为变化）：
;; · 按住式（mouse-1 down/up 对）——Android 触屏的 mouse-1 在抬手时
;;   才合成（无「按住期间」），长按 0.7s 被系统拖选手势占用（Mark set）。

(defvar custom/touch--lock-mode nil
  "锁定模式：C/M/S 点按改为叠加锁定修饰。")
(defvar custom/touch--locked-mods nil
  "已锁定的修饰符列表（如 (control meta) → 键盘输入带 C-M-）。")

(declare-function custom/bar--render "init-bar")

(defun custom/touch--mod-prefix (mod)
  "修饰符 MOD 的键前缀字符串。"
  (pcase mod ('control "C-") ('meta "M-") ('shift "S-")))

(defun custom/touch--lock-chars ()
  "参与翻译的字符列表（小写字母 + 数字）。"
  (append "abcdefghijklmnopqrstuvwxyz0123456789" nil))

(defun custom/touch--refresh-lock-translation ()
  "按当前锁定集合重装字母翻译。"
  (dolist (c (custom/touch--lock-chars))
    (define-key key-translation-map (char-to-string c) nil))
  (when custom/touch--locked-mods
    (let ((prefix (mapconcat #'custom/touch--mod-prefix
                             custom/touch--locked-mods "")))
      (dolist (c (custom/touch--lock-chars))
        (let ((key-str (char-to-string c)))
          (define-key key-translation-map key-str
            (lambda (_prompt)
              (kbd (concat prefix key-str)))))))))

(defun custom/touch-lock-toggle ()
  "修饰锁定模式开关：开启后点 C/M/S 叠加锁定，再点本按钮清除关闭。"
  (interactive)
  (setq custom/touch--lock-mode (not custom/touch--lock-mode)
        custom/touch--locked-mods nil)
  (custom/touch--refresh-lock-translation)
  (message (if custom/touch--lock-mode
               "修饰锁定开：点 C/M/S 叠加锁定"
             "修饰锁定关"))
  (custom/bar--render))

(defun custom/touch--toggle-lock (mod)
  "锁定模式下切换修饰符 MOD 的锁定状态。"
  (if (memq mod custom/touch--locked-mods)
      (setq custom/touch--locked-mods (delq mod custom/touch--locked-mods))
    (push mod custom/touch--locked-mods))
  (custom/touch--refresh-lock-translation)
  (message "锁定: %s"
           (if custom/touch--locked-mods
               (mapconcat #'custom/touch--mod-prefix
                          custom/touch--locked-mods "")
             "无"))
  (custom/bar--render))

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
  "锁定模式下锁定/解锁 Ctrl；否则下一个输入加 Ctrl。"
  (interactive)
  (if custom/touch--lock-mode
      (custom/touch--toggle-lock 'control)
    (custom/touch--one-shot #'event-apply-control-modifier "C")))

(defun custom/touch-meta-modifier ()
  "锁定模式下锁定/解锁 Meta；否则下一个输入加 Meta。"
  (interactive)
  (if custom/touch--lock-mode
      (custom/touch--toggle-lock 'meta)
    (custom/touch--one-shot #'event-apply-meta-modifier "M")))

(defun custom/touch-shift-modifier ()
  "锁定模式下锁定/解锁 Shift；否则下一个输入加 Shift。"
  (interactive)
  (if custom/touch--lock-mode
      (custom/touch--toggle-lock 'shift)
    (custom/touch--one-shot #'event-apply-shift-modifier "S")))

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
