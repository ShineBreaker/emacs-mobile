;;; init-markdown.el --- Markdown 栈：gfm 编辑 + view 渲染查看 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; markdown-mode 单包承载编辑与查看，纯 elisp 无外部命令依赖
;; （pandoc 仅 HTML 导出才需要）：gfm-mode 编辑（代码块原生高亮），
;; gfm-view-mode 只读渲染查看（隐藏标记与 URL、列表符显圆点、
;; 表格 overlay 渲染框线：列宽按窗口预算分配、cell 内折行，
;; CJK 按实宽对齐）。
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

(defvar-local custom/markdown--table-last-width nil
  "上次表格渲染的窗宽预算，窗宽变化时重排。")

(defun custom/markdown--disp-width (string)
  "STRING 实显列宽：框线字符（East Asian Ambiguous，CJK 语言环境
`char-width' 计 2、等宽字体实占 1 列）按 1 计，其余按 `char-width'。"
  (let ((w 0) (i 0))
    (while (< i (length string))
      (let* ((ch (aref string i))
             (cw (char-width ch)))
        (setq w (+ w (if (and (= cw 2) (>= ch #x2500) (<= ch #x257f)) 1 cw))
              i (1+ i))))
    w))

(defun custom/markdown--table-budget ()
  "表格可用总列数：当前窗口宽，无窗口时退 60。"
  (let ((w (get-buffer-window (current-buffer))))
    (if w (window-body-width w) 60)))

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

(defun custom/markdown--wrap (string width)
  "按显示宽贪心折 STRING 为段列表（各段显示宽 ≤ WIDTH），保留属性。
断点优先行内空格（保词完整），空格断点不足半行宽时硬切（CJK 长串）。"
  (let (segs)
    (while (> (string-width string) width)
      (let ((cut 0) (col 0) space space-col done)
        (while (and (not done) (< cut (length string)))
          (let ((ch (aref string cut)))
            (if (= ch ?\s)
                (setq space cut space-col col
                      col (1+ col) cut (1+ cut))
              (let ((nc (+ col (char-width ch))))
                (if (> nc width)
                    (setq done t)
                  (setq col nc cut (1+ cut)))))))
        (cond ((and space (>= space-col (/ width 2)))
               (setq segs (cons (substring string 0 space) segs)
                     string (substring string (1+ space))))
              ((zerop cut)
               ;; 首字符自身超宽（width < 单字符宽的退化情况）
               (setq segs (cons (substring string 0 1) segs)
                     string (substring string 1)))
              (t
               (setq segs (cons (substring string 0 cut) segs)
                     string (substring string cut))))))
    (append (nreverse segs) (list string))))

(defun custom/markdown--pad (text width align)
  "按显示宽把 TEXT 补到 WIDTH 列（ALIGN：r 右 c 居中，余左）。"
  (let ((pad (max 0 (- width (string-width text)))))
    (pcase align
      ('r (concat (make-string pad ?\s) text))
      ('c (let ((l (/ pad 2)))
            (concat (make-string l ?\s) text (make-string (- pad l) ?\s))))
      (_ (concat text (make-string pad ?\s))))))

(defun custom/markdown--table-widths (nat budget)
  "NAT 各列自然宽分配总预算 BUDGET：装得下用自然宽，装不下保底
4 列余量按超宽比例分摊，舍入余数并入最宽列。"
  (if (<= (apply #'+ nat) budget)
      nat
    (let* ((minw 4)
           (n (length nat))
           (rem (max 0 (- budget (* n minw))))
           (extra (mapcar (lambda (w) (max 0 (- w minw))) nat))
           (sum (apply #'+ extra)))
      (if (zerop sum)
          (make-list n minw)
        (let ((ws (mapcar (lambda (e)
                            (+ minw (max 0 (floor (* rem (/ (float e)
                                                            sum))))))
                          extra))
              (mx 0))
          (setq rem (- budget (apply #'+ ws)))
          (dotimes (i n)
            (when (> (nth i extra) (nth mx extra)) (setq mx i)))
          (when (> rem 0)
            (setcar (nthcdr mx ws) (+ (nth mx ws) rem)))
          ws)))))

(defun custom/markdown--table-rule (widths left mid right)
  "框线行：LEFT/MID/RIGHT 为角与三通字符，列宽取 WIDTHS。"
  (concat left
          (mapconcat (lambda (w) (make-string (+ w 2) ?─)) widths mid)
          right))

(defun custom/markdown--table-lines (cells widths aligns)
  "CELLS 为各 cell 的折行段列表，组装该逻辑行的框线行列表。
行高取最高 cell，空位补空白；仅单行 cell 按列对齐。"
  (let ((h (apply #'max 1 (mapcar #'length cells)))
        out)
    (dotimes (row h)
      (push
       (concat "│"
               (mapconcat
                (lambda (i)
                  (let* ((lines (nth i cells))
                         (align (and (= (length lines) 1) (nth i aligns))))
                    (concat " "
                            (custom/markdown--pad (or (nth row lines) "")
                                                  (nth i widths) align)
                            " ")))
                (number-sequence 0 (1- (length widths)))
                "│")
               "│")
       out))
    (nreverse out)))

(defun custom/markdown--render-table (beg end)
  "把 BEG..END 表格 overlay 渲染为框线表，不改源文本。
列宽按窗口预算分配，超宽 cell 段内折行（真机窄屏框线不断）。"
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
      (let* ((ncol (apply #'max (mapcar #'length rows)))
             (idxs (number-sequence 0 (1- ncol)))
             (cells (mapcar (lambda (r)
                              (mapcar #'custom/markdown--cell-render
                                      (append r (make-list (- ncol (length r))
                                                           ""))))
                            rows))
             (budget (max (- (custom/markdown--table-budget)
                             (* 3 ncol) 1)
                          (* ncol 4)))
             (widths (custom/markdown--table-widths
                      (mapcar (lambda (i)
                                (apply #'max 1 (mapcar
                                                (lambda (c)
                                                  (string-width (nth i c)))
                                                cells)))
                              idxs)
                      budget))
             (aligns (markdown-table-colfmt fmtspec))
             (cells-w (mapcar (lambda (r)
                                (let (out)
                                  (dotimes (i ncol)
                                    (push (custom/markdown--wrap
                                           (nth i r) (nth i widths)) out))
                                  (nreverse out)))
                              cells))
             (body (list (custom/markdown--table-rule widths "┌" "┬" "┐"))))
        (let ((head (mapcar (lambda (lines)
                              (mapcar (lambda (s)
                                        (propertize s 'face 'bold))
                                      lines))
                            (pop cells-w))))
          (setq body (append body
                             (custom/markdown--table-lines head widths aligns)
                             (list (custom/markdown--table-rule
                                    widths "├" "┼" "┤")))))
        (dolist (r cells-w)
          (setq body (append body (custom/markdown--table-lines
                                   r widths aligns))))
        (setq body (append body
                           (list (custom/markdown--table-rule
                                  widths "└" "┴" "┘"))))
        (let ((ov (make-overlay beg end)))
          (overlay-put ov 'display (mapconcat #'identity body "\n"))
          (overlay-put ov 'custom-markdown-table t)
          (push ov custom/markdown--table-overlays))))))

(defun custom/markdown--tables-clear ()
  "撤销查看态表格渲染 overlay。"
  (mapc #'delete-overlay custom/markdown--table-overlays)
  (setq custom/markdown--table-overlays nil
        custom/markdown--table-last-width nil))

(defun custom/markdown--tables-render ()
  "渲染 buffer 内全部表格（幂等，先清旧 overlay），记录窗宽预算。"
  (custom/markdown--tables-clear)
  (setq custom/markdown--table-last-width (custom/markdown--table-budget))
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

(defun custom/markdown--tables-refit ()
  "窗宽变化（旋转屏）时重排表格渲染。"
  (when (and custom/markdown--table-overlays
             (/= (custom/markdown--table-budget)
                 (or custom/markdown--table-last-width 0)))
    (custom/markdown--tables-render)))

(defun custom/markdown--setup ()
  "gfm 系 buffer：右端钮组前插入 markdown 钮。
gfm-view-mode 进入时父链 hook 亦经过此函数，按当前态选钮组。"
  (if (derived-mode-p 'gfm-view-mode)
      (progn
        ;; 查看态是展示型 read-only buffer：tap 不唤键盘，表格渲染为
        ;; 框线表（cell 内折行），窗宽变化重排
        (custom/touch-no-keyboard)
        (custom/markdown--tables-render)
        (add-hook 'window-configuration-change-hook
                  #'custom/markdown--tables-refit nil t))
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
