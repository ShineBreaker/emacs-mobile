;;; init-markdown.el --- Markdown 栈：gfm 编辑 + view 渲染查看 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; markdown-mode 单包承载编辑与查看，纯 elisp 无外部命令依赖
;; （pandoc 仅 HTML 导出才需要）：gfm-mode 编辑（代码块原生高亮），
;; 查看走专用展示 buffer（同窗切换）：gfm-view-mode 隐藏标记与
;; URL、列表符显圆点，表格替换为 ASCII 框线真文本（列宽按窗口
;; 预算分配、cell 内折行，CJK 按实宽对齐）。真文本而非 overlay：
;; display overlay 钉死 window-start，触摸滚动在表格区推不动。
;; 触屏入口走 mode-line 钮（dired 先例）：编辑态粗/斜/码包裹选区 +
;; 视图切换，查看态仅保留返回编辑钮。

;;; Code:

(declare-function custom/touch-no-keyboard "init-touch")
(declare-function custom/mode-line--button "init-ui")
(declare-function custom/mode-line--add-local-buttons "init-ui")
(declare-function gfm-mode "markdown-mode")
(declare-function gfm-view-mode "markdown-mode")
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

;; ─── 表格渲染核心：纯文本进出，供展示 buffer 真文本替换 ──────────

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

(defun custom/markdown--table-rule (widths)
  "框线行。org 风格 ASCII：真机把 box-drawing 字符渲染为全角
2 列，框线行与内容行宽度必然失衡，全 ASCII 才能实宽对齐。"
  (concat "+"
          (mapconcat (lambda (w) (make-string (+ w 2) ?-)) widths "+")
          "+"))

(defun custom/markdown--table-lines (cells widths aligns)
  "CELLS 为各 cell 的折行段列表，组装该逻辑行的框线行列表。
行高取最高 cell，空位补空白；仅单行 cell 按列对齐。"
  (let ((h (apply #'max 1 (mapcar #'length cells)))
        out)
    (dotimes (row h)
      (push
       (concat "|"
               (mapconcat
                (lambda (i)
                  (let* ((lines (nth i cells))
                         (align (and (= (length lines) 1) (nth i aligns))))
                    (concat " "
                            (custom/markdown--pad (or (nth row lines) "")
                                                  (nth i widths) align)
                            " ")))
                (number-sequence 0 (1- (length widths)))
                "|")
               "|")
       out))
    (nreverse out)))

(defun custom/markdown--table-render (text budget)
  "表格源 TEXT 渲染为框线表文本（列宽总预算 BUDGET 列）。"
  (let* ((lines (split-string text "\n" t))
         fmtspec rows)
    (dolist (line lines)
      (cond ((or (markdown--is-delimiter-row line)
                 ;; GFM 简化表分隔行（无首尾管道）：---|---
                 (string-match-p "\\`[-:][|:- \t]*\\'" line))
             (unless fmtspec (setq fmtspec line)))
            (t (push (markdown--table-line-to-columns line) rows))))
    (if (not rows)
        text
      (setq rows (nreverse rows))
      (let* ((ncol (apply #'max (mapcar #'length rows)))
             (idxs (number-sequence 0 (1- ncol)))
             (cells (mapcar (lambda (r)
                              (mapcar #'custom/markdown--cell-render
                                      (append r (make-list (- ncol (length r))
                                                           ""))))
                            rows))
             (budget (max (- budget (* 3 ncol) 3) (* ncol 4)))
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
             (body (list (custom/markdown--table-rule widths))))
        (let ((head (mapcar (lambda (lines)
                              (mapcar (lambda (s)
                                        (propertize s 'face 'bold))
                                      lines))
                            (pop cells-w))))
          (setq body (append body
                             (custom/markdown--table-lines head widths aligns)
                             (list (custom/markdown--table-rule widths)))))
        (dolist (r cells-w)
          (setq body (append body (custom/markdown--table-lines
                                   r widths aligns))))
        (setq body (append body
                           (list (custom/markdown--table-rule widths))))
        (mapconcat #'identity body "\n")))))

(defun custom/markdown--table-budget (window)
  "表格可用总列数：WINDOW 正文像素宽扣除行号区，按当前显示
字体（感知 text-scale remap）折列；WINDOW nil 退 60。"
  (if window
      (floor (/ (- (window-body-width window t)
                   (line-number-display-width window))
                (window-font-width window)))
    60))

(defun custom/markdown--tables-insert (budget)
  "当前 buffer（原文态）内全部表格替换为框线真文本（BUDGET 列）。"
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp))
      (if (markdown-table-at-point-p)
          (let* ((beg (markdown-table-begin))
                 (end (markdown-table-end))
                 (text (buffer-substring-no-properties beg end))
                 (rendered (custom/markdown--table-render text budget)))
            (delete-region beg end)
            (insert rendered "\n")
            (forward-line 1))
        (forward-line 1)))))

;; ─── 查看态：专用展示 buffer（真文本，触摸滚动平滑） ──────────────

(defvar-local custom/markdown--src-buffer nil
  "展示 buffer 的源编辑 buffer。")

(defun custom/markdown--view-name (src)
  "源 buffer SRC 对应的展示 buffer 名。"
  (format "*视·%s*" (buffer-name src)))

(defun custom/markdown--view-generate (src &optional keep-pos)
  "从 SRC 生成（或重生成）展示 buffer 并返回之。
KEEP-POS 为起始行文本时，生成后把该 buffer 的窗滚回此行。"
  (let* ((win (or (get-buffer-window src t) (selected-window)))
         (budget (custom/markdown--table-budget win))
         (content (with-current-buffer src (buffer-string))))
    (with-current-buffer (get-buffer-create (custom/markdown--view-name src))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert content))
      (gfm-view-mode)
      ;; buffer-local 变量须在 major mode 之后设：mode 函数的
      ;; kill-all-local-variables 会抹掉先设的局部绑定
      (setq custom/markdown--src-buffer src
            custom/markdown--view-last-budget budget)
      ;; 先 fontify 完整原文（code-block 标记就位），代码块内的
      ;; 假表格才不会被误当表格替换
      (font-lock-ensure)
      (let ((inhibit-read-only t))
        (custom/markdown--tables-insert budget))
      (when keep-pos
        (goto-char (point-min))
        (when (search-forward keep-pos nil t)
          (beginning-of-line)
          (when (get-buffer-window (current-buffer) t)
            (set-window-start (get-buffer-window (current-buffer) t)
                              (point)))))
      (current-buffer))))

(defun custom/markdown--view-refit ()
  "展示 buffer 窗宽/字号变化后重新生成（保持滚动位置）。"
  (let* ((win (get-buffer-window (current-buffer) t))
         (anchor (and win
                      (buffer-substring-no-properties
                       (window-start win) (line-end-position)))))
    (custom/markdown--view-generate custom/markdown--src-buffer anchor)))

(defvar-local custom/markdown--view-last-budget nil
  "展示 buffer 上次生成的列宽预算，变化时重生成。")

(defun custom/markdown--view-refit-maybe ()
  "窗宽或字号变化（预算改变）时重生成展示 buffer。"
  (when custom/markdown--src-buffer
    (let* ((budget (custom/markdown--table-budget
                    (get-buffer-window (current-buffer) t)))
           (changed (and budget custom/markdown--view-last-budget
                         (/= budget custom/markdown--view-last-budget))))
      (setq custom/markdown--view-last-budget budget)
      (when changed
        (custom/markdown--view-refit)))))

(defun custom/markdown--view-refit-soon ()
  "字号变化（text-scale）后延迟一拍重排：hook 先于 redisplay，
列宽此时未更新。"
  (when custom/markdown--src-buffer
    (run-at-time 0 nil #'custom/markdown--view-refit-maybe)))

(defun custom/markdown-toggle-view ()
  "gfm 编辑与渲染查看互切（查看走专用展示 buffer，同窗切换）。"
  (interactive)
  (if custom/markdown--src-buffer
      ;; 展示 buffer → 返回编辑
      (if (buffer-live-p custom/markdown--src-buffer)
          (switch-to-buffer custom/markdown--src-buffer)
        (kill-current-buffer))
    ;; 编辑 buffer → 生成展示 buffer 并同窗显示
    (set-window-buffer
     (selected-window)
     (custom/markdown--view-generate (current-buffer)))))

;; ─── mode-line 钮（dired 先例） ─────────────────────────────────────

(defconst custom/markdown--edit-buttons
  '(("\uF032" "粗" "粗体（无选区插入标记，有选区包裹）" markdown-insert-bold)
    ("\uF033" "斜" "斜体（无选区插入标记，有选区包裹）" markdown-insert-italic)
    ("\uF121" "码" "行内代码（无选区插入标记，有选区包裹）" markdown-insert-code)
    ("\uF06E" "视" "切换到渲染查看" custom/markdown-toggle-view))
  "编辑态 mode-line 钮表：(NF 字形 tty 回退 帮助 命令)。")

(defconst custom/markdown--view-buttons
  '(("\uF06E" "视" "返回编辑" custom/markdown-toggle-view))
  "查看态 mode-line 钮表。")

(defun custom/markdown--buttons ()
  "当前态（编辑/查看）对应的 mode-line 钮串。
钮前导 2 列（右端钮组同款），四钮 + 右端钮组共存。"
  (mapconcat
   #'custom/mode-line--button
   (if (derived-mode-p 'gfm-view-mode)
       custom/markdown--view-buttons
     custom/markdown--edit-buttons)
   nil))

(defun custom/markdown--setup ()
  "gfm 系 buffer：右端钮组前插入 markdown 钮。
gfm-view-mode 进入时父链 hook 亦经过此函数，按当前态选钮组。"
  (when (derived-mode-p 'gfm-view-mode)
    ;; 展示型 read-only buffer：tap 不唤键盘、不显行号（编辑区
    ;; 行号挂 text-mode-hook，本 hook 在其后，关闭生效）
    (custom/touch-no-keyboard)
    (display-line-numbers-mode -1)
    (add-hook 'window-configuration-change-hook
              #'custom/markdown--view-refit-maybe nil t)
    (add-hook 'text-scale-mode-hook
              #'custom/markdown--view-refit-soon nil t))
  (custom/mode-line--add-local-buttons #'custom/markdown--buttons))

(add-hook 'gfm-mode-hook #'custom/markdown--setup)

(provide 'init-markdown)
;;; init-markdown.el ends here
