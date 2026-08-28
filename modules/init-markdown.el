;;; init-markdown.el --- Markdown 栈：gfm 编辑 + view 渲染查看 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; markdown-mode 单包承载编辑与查看，纯 elisp 无外部命令依赖
;; （pandoc 仅 HTML 导出才需要）：gfm-mode 编辑（代码块原生高亮），
;; gfm-view-mode 只读渲染查看（隐藏标记与 URL、列表符显圆点、
;; 表格 overlay 渲染框线，CJK 按实宽对齐）。
;; 触屏入口走 mode-line 钮（dired 先例）：编辑态粗/斜/码包裹选区 +
;; 视图切换，查看态仅保留返回编辑钮。

;;; Code:

(declare-function custom/glyph "init-basis")
(declare-function custom/touch-no-keyboard "init-touch")
(declare-function gfm-mode "markdown-mode")
(declare-function gfm-view-mode "markdown-mode")
(declare-function markdown-code-block-at-point-p "markdown-mode")
(declare-function markdown-table-at-point-p "markdown-mode")
(declare-function markdown-table-begin "markdown-mode")
(declare-function markdown-table-end "markdown-mode")
(declare-function markdown-table-colfmt "markdown-mode")
(declare-function markdown--table-line-to-columns "markdown-mode")
(declare-function markdown--is-delimiter-row "markdown-mode")

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
间隔 2 列（右端钮组同款），四钮 + 右端钮组共存。"
  (pcase-let ((`(,glyph ,fallback ,help ,command) spec))
    (propertize
     (format "  %s" (custom/glyph glyph fallback))
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

(defvar-local custom/markdown--table-overlays nil
  "查看态表格渲染 overlay，切回编辑态整体撤销。")

(defun custom/markdown--cell-plain (text)
  "剥 cell 行内强调标记与链接，供表格渲染显示。"
  (setq text (replace-regexp-in-string "\\\\|" "|" text))
  (setq text (replace-regexp-in-string "!\\?\\[\\([^]]*\\)\\]([^)]*)" "\\1" text))
  (dolist (re '("\\*\\*\\([^*]+\\)\\*\\*" "__\\([^_]+\\)__"
                "~~\\([^~]+\\)~~" "==\\([^=]+\\)==" "\\*\\([^*]+\\)\\*"))
    (setq text (replace-regexp-in-string re "\\1" text)))
  text)

(defun custom/markdown--cell-render (cell)
  "CELL 原文 → 渲染串：剥行内标记，`code` 段保留原文加 code face。"
  (let ((i 0) out)
    (dolist (seg (split-string cell "`") (mapconcat #'identity (nreverse out) ""))
      (push (if (= (logand i 1) 1)
                (propertize seg 'face 'markdown-inline-code-face)
              (custom/markdown--cell-plain seg))
            out)
      (setq i (1+ i)))))

(defun custom/markdown--pad (text width align)
  "按显示宽把 TEXT 补到 WIDTH 列（ALIGN：r 右 c 居中，余左）。"
  (let ((pad (max 0 (- width (string-width text)))))
    (pcase align
      ('r (concat (make-string pad ?\s) text))
      ('c (let ((l (/ pad 2)))
            (concat (make-string l ?\s) text (make-string (- pad l) ?\s))))
      (_ (concat text (make-string pad ?\s))))))

(defun custom/markdown--table-rule (widths left mid right)
  "框线行：LEFT/MID/RIGHT 为角与三通字符，列宽取 WIDTHS。"
  (concat left
          (mapconcat (lambda (w) (make-string (+ w 2) ?─)) widths mid)
          right))

(defun custom/markdown--table-row (cells widths aligns)
  "数据行：CELLS 为渲染串，少列补空，宽与对齐按 WIDTHS/ALIGNS。"
  (concat "│"
          (mapconcat
           (lambda (i)
             (concat " "
                     (custom/markdown--pad (or (nth i cells) "")
                                           (nth i widths) (nth i aligns))
                     " "))
           (number-sequence 0 (1- (length widths)))
           "│")
          "│"))

(defun custom/markdown--render-table (beg end)
  "把 BEG..END 的表格以 overlay display 渲染为框线表，不改源文本。
列宽按 `string-width' 计（CJK 实宽），对齐符复用包的 colfmt 解析。"
  (let* ((lines (split-string (buffer-substring beg end) "\n" t))
         fmtspec rows)
    (dolist (line lines)
      (cond ((or (markdown--is-delimiter-row line)
                 ;; GFM 简化表分隔行（无首尾管道）：---|---
                 (string-match-p "\\`[-:][|:- \t]*\\'" line))
             (unless fmtspec (setq fmtspec line)))
            (t (push (markdown--table-line-to-columns line) rows))))
    (when rows
      (setq rows (nreverse rows))
      (let* ((idxs (number-sequence
                    0 (1- (apply #'max (mapcar #'length rows)))))
             (widths (mapcar
                      (lambda (i)
                        (apply #'max 1
                               (mapcar (lambda (r)
                                         (string-width
                                          (custom/markdown--cell-render
                                           (or (nth i r) ""))))
                                       rows)))
                      idxs))
             (aligns (markdown-table-colfmt fmtspec))
             body)
        (push (custom/markdown--table-rule widths "┌" "┬" "┐") body)
        (push (custom/markdown--table-row
               (mapcar (lambda (s) (propertize s 'face 'bold))
                       (mapcar #'custom/markdown--cell-render (pop rows)))
               widths aligns)
              body)
        (push (custom/markdown--table-rule widths "├" "┼" "┤") body)
        (dolist (r rows)
          (push (custom/markdown--table-row
                 (mapcar #'custom/markdown--cell-render r) widths aligns)
                body))
        (push (custom/markdown--table-rule widths "└" "┴" "┘") body)
        (let ((ov (make-overlay beg end)))
          (overlay-put ov 'display (mapconcat #'identity (nreverse body) "\n"))
          (overlay-put ov 'custom-markdown-table t)
          (push ov custom/markdown--table-overlays))))))

(defun custom/markdown--tables-clear ()
  "撤销查看态表格渲染 overlay。"
  (mapc #'delete-overlay custom/markdown--table-overlays)
  (setq custom/markdown--table-overlays nil))

(defun custom/markdown--tables-render ()
  "渲染 buffer 内全部表格（幂等，先清旧 overlay）。"
  (custom/markdown--tables-clear)
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (while (not (eobp))
        (if (markdown-table-at-point-p)
            (let ((beg (markdown-table-begin))
                  (end (markdown-table-end)))
              (custom/markdown--render-table beg end)
              (goto-char end))
          (forward-line 1))))))

(defun custom/markdown--setup ()
  "gfm 系 buffer：右端钮组前插入 markdown 钮。
gfm-view-mode 进入时父链 hook 亦经过此函数，按当前态选钮组。"
  (if (derived-mode-p 'gfm-view-mode)
      ;; 查看态是展示型 read-only buffer：tap 不唤键盘，表格渲染为框线
      (progn (custom/touch-no-keyboard)
             (custom/markdown--tables-render))
    ;; 编辑态（含从查看态切回）：撤销表格渲染
    (custom/markdown--tables-clear))
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
