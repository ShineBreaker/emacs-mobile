;;; init-markdown.el --- Markdown 栈：gfm 编辑 + view 渲染查看 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; markdown-mode 单包承载编辑与查看，纯 elisp 无外部命令依赖
;; （pandoc 仅 HTML 导出才需要）：gfm-mode 编辑（代码块原生高亮），
;; gfm-view-mode 只读渲染查看（隐藏标记与 URL、列表符显圆点）。
;; 触屏入口走 mode-line 钮（dired 先例）：编辑态粗/斜/码包裹选区 +
;; 视图切换，查看态仅保留返回编辑钮。

;;; Code:

(declare-function custom/glyph "init-basis")
(declare-function custom/touch-no-keyboard "init-touch")
(declare-function gfm-mode "markdown-mode")
(declare-function gfm-view-mode "markdown-mode")

(use-package markdown-mode
  :mode (("\\.md\\'" . gfm-mode)
         ("\\.markdown\\'" . gfm-mode))
  :custom
  ;; 代码块按语言原生高亮（= org-src-fontify-natively）
  (markdown-fontify-code-blocks-natively t))

(defun custom/markdown-toggle-view ()
  "gfm 编辑与只读渲染查看互切（同 buffer 切 major mode，不弹窗）。"
  (interactive)
  (if (derived-mode-p 'gfm-view-mode)
      (gfm-mode)
    (gfm-view-mode)))

(defconst custom/markdown--edit-buttons
  '(("\uF032" "粗" "粗体（无选区插入标记，有选区包裹）" markdown-insert-bold)
    ("\uF033" "斜" "斜体（无选区插入标记，有选区包裹）" markdown-insert-italic)
    ("\uF121" "码" "行内代码（无选区插入标记，有选区包裹）" markdown-insert-code)
    ("\uF06E" "视" "切换到渲染查看" custom/markdown-toggle-view))
  "编辑态 mode-line 钮表：(NF 字形 tty 回退 帮助 命令)。")

(defconst custom/markdown--view-buttons
  '(("\uF06E" "视" "返回编辑" custom/markdown-toggle-view))
  "查看态 mode-line 钮表。")

(defun custom/markdown--button (spec)
  "按 SPEC（字形 回退 帮助 命令）构造单颗 mode-line 钮。
间隔 1 列（dired 同款）：40 列窄屏下四钮 + 右端钮组须共存。"
  (pcase-let ((`(,glyph ,fallback ,help ,command) spec))
    (propertize
     (format " %s" (custom/glyph glyph fallback))
     'local-map (make-mode-line-mouse-map 'mouse-1 command)
     'mouse-face 'highlight
     'help-echo help)))

(defun custom/markdown--buttons ()
  "当前态（编辑/查看）对应的 mode-line 钮串。"
  (mapconcat
   #'custom/markdown--button
   (if (derived-mode-p 'gfm-view-mode)
       custom/markdown--view-buttons
     custom/markdown--edit-buttons)
   nil))

(defun custom/markdown--setup ()
  "gfm 系 buffer：右端钮组前插入 markdown 钮。
gfm-view-mode 进入时父链 hook 亦经过此函数，按当前态选钮组。"
  (when (derived-mode-p 'gfm-view-mode)
    ;; 查看态是展示型 read-only buffer，tap 不唤键盘
    (custom/touch-no-keyboard))
  (let* ((fmt (default-value 'mode-line-format))
         (pos (seq-position fmt '(:eval (custom/mode-line--right-space)))))
    (when pos
      (setq-local mode-line-format
                  (append (seq-take fmt pos)
                          (list '(:eval (custom/markdown--buttons)))
                          (seq-drop fmt pos))))))

(add-hook 'gfm-mode-hook #'custom/markdown--setup)

(provide 'init-markdown)
;;; init-markdown.el ends here
