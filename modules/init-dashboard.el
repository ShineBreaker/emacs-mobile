;;; init-dashboard.el --- 启动仪表盘（盲文 logo + [] 按钮视觉体系） -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; dashboard master 自带 Android 触屏修复（widget 点击走 mouse-1 与
;; <touchscreen-begin> 双通道），条目零改造可点。
;; 窄屏（约 40 列）视觉体系：
;; · hero：官方盲文 Emacs logo（30×14，行等宽块居中）+ 时段问候·
;;   随机小句 + 日期/启动信息行
;; · navigator 三枚 [] 按钮（括号 dim、内文 bold）
;; · 各段 heading 短装饰线 + NF 图标夹标题，条目间空行（4+4）
;; · footer 英文短名言随机（长度 ≤40 列不折行）
;; · tty 无 NF 字形自动降级纯文本

;;; Code:

(straight-use-package 'dashboard)

(require 'dashboard)

;; ─── faces ──────────────────────────────────────────────────────────

(defface custom/dashboard-logo
  '((t :inherit font-lock-keyword-face :weight bold))
  "盲文 logo（主题关键词单色）。" :group 'emacs-mobile)

(defface custom/dashboard-hero
  '((t :weight bold :height 1.5))
  "抓笔记面板大标题。" :group 'emacs-mobile)

(defface custom/dashboard-subtitle
  '((t :inherit font-lock-doc-face :height 0.9))
  "仪表盘问候行。" :group 'emacs-mobile)

(defface custom/dashboard-deco
  '((t :inherit shadow))
  "装饰线与按钮括号。" :group 'emacs-mobile)

(defface custom/dashboard-deco-icon
  '((t :inherit font-lock-keyword-face))
  "装饰线/条目中的 NF 图标。" :group 'emacs-mobile)

(defface custom/dashboard-meta
  '((t :inherit shadow))
  "日期/启动信息行。" :group 'emacs-mobile)

(defface custom/dashboard-button
  '((t :weight bold))
  "navigator 按钮文字。" :group 'emacs-mobile)

;; ─── 声明 ───────────────────────────────────────────────────────────

(declare-function custom/glyph "init-basis")
(declare-function custom/org--ensure-directories "init-org")
(declare-function custom/org--ensure-agenda-file "init-org")
(declare-function custom/touch-show-keyboard "init-touch")
(defvar custom:org-directory)
(defvar custom:org-roam-directory)
(defvar org-capture-templates)

;; ─── hero：盲文 logo + 问候 + 日期/启动信息 ─────────────────────────

(defconst custom/dashboard--mottos
  '("今天也要 org-mode" "万物皆 buffer" "写下来就成功了一半"
    "慢慢来比较快" "一切皆文本，一切可编程")
  "问候行随机小句池。")

(defun custom/dashboard--greeting ()
  "按时段返回中文问候。"
  (let ((h (nth 2 (decode-time))))
    (cond ((<= 5 h 7) "晨光正好")
          ((<= 8 h 10) "上午好，日光正盛")
          ((<= 11 h 12) "午安")
          ((<= 13 h 16) "日色渐西")
          ((<= 17 h 18) "暮色四合")
          ((<= 19 h 22) "夜色温柔")
          (t "夜深了"))))

(defun custom/dashboard--info-line ()
  "日期与启动信息短行。"
  (let* ((now (decode-time))
         (week (nth (nth 6 now)
                    '("周日" "周一" "周二" "周三" "周四" "周五" "周六"))))
    (format "%d月%d日 %s · %d 包 · %.2fs"
            (nth 4 now) (nth 3 now) week
            (dashboard-init--packages-count)
            (string-to-number (emacs-init-time)))))

(defun custom/dashboard-insert-hero ()
  "hero 区：盲文 logo（块居中保持图形）+ 问候行 + 日期/启动信息行。
问候 + 小句组合超 36 列时省略小句（窄屏防折行）。"
  (insert "\n")
  (let ((start (point)))
    (insert (propertize
             (with-temp-buffer
               (insert-file-contents dashboard-banner-logo-braille)
               (buffer-string))
             'face 'custom/dashboard-logo))
    (dashboard-center-text start (point)))
  (insert "\n")
  (let* ((greet (custom/dashboard--greeting))
         (motto (nth (random (length custom/dashboard--mottos))
                     custom/dashboard--mottos))
         (line (format "%s · %s" greet motto)))
    (dashboard-insert-center
     (propertize (if (<= (string-width line) 36) line greet)
                 'face 'custom/dashboard-subtitle)))
  (insert "\n")
  (dashboard-insert-center
   (propertize (custom/dashboard--info-line) 'face 'custom/dashboard-meta))
  (insert "\n"))

;; ─── heading：中文标题 + NF 图标 + 两侧短装饰线 ─────────────────────
;; 标题直接用中文 buffer 文本：`dashboard--find-max-width' 按 buffer
;; 原文计宽，overlay display 换名不参与计算。

(defun custom/dashboard--heading-icon (code)
  "返回码点 CODE 的图标串。"
  (propertize code 'face 'custom/dashboard-deco-icon))

(defun custom/dashboard-insert-heading-deco (fn heading &optional shortcut icon)
  "HEADING 两侧加短装饰线（整行居中由 `dashboard-center-content' 统一做）。"
  (prog1 (funcall fn heading shortcut icon)
    (let ((deco (propertize "──── " 'face 'custom/dashboard-deco)))
      (save-excursion
        ;; icon 回退须与官方插入条件一致（tty 无字形不插入 icon）
        (goto-char (- (point) (length heading)))
        (when (and (dashboard-display-icons-p) dashboard-set-heading-icons icon)
          (goto-char (- (point) (1+ (length icon)))))
        (insert deco)))
    (insert (propertize " ────" 'face 'custom/dashboard-deco))))

(advice-add #'dashboard-insert-heading :around
            #'custom/dashboard-insert-heading-deco)

;; ─── items 区逐行居中 ───────────────────────────────────────────────
;; 官方 `dashboard-center-content' 是块居中：条目区共用一个前缀、块内
;; 左对齐，最宽行决定偏移，窄屏下标题/短条目明显偏左。改为各行按
;; 自身宽居中；宽度用官方 `dashboard-str-len'（像素法）——歧义宽字符
;; （─ 等）string-width 记 1 列但 Maple 实渲 2 列，像素法真机精确。

(defun custom/dashboard-center-lines (&rest _)
  "items 区各行按可见内容宽重设居中前缀（覆盖官方块居中前缀）。
条目行的前导缩进空格不计入居中宽度，并补入偏移使其推到不可见侧。"
  (let ((start (car (last dashboard--section-starts))))
    (when start
      (save-excursion
        (goto-char start)
        (while (< (point) (point-max))
          (let* ((bol (line-beginning-position))
                 (eol (line-end-position))
                 (txt (buffer-substring bol eol))
                 (lead (progn (string-match "\\` *" txt)
                              (match-end 0)))
                 (w (dashboard-str-len (substring txt lead))))
            (when (> w 0)
              (let ((prefix (propertize
                             " " 'display
                             `(space . (:align-to (- center
                                                     ,(+ (/ w 2.0) lead)))))))
                (add-text-properties bol eol
                                     `(line-prefix ,prefix
                                       wrap-prefix ,prefix)))))
          (forward-line 1))))))

(advice-add #'dashboard-insert-items :after #'custom/dashboard-center-lines)

;; ─── 窄屏条目标签截断 ───────────────────────────────────────────────

(defun custom/dashboard--take-width (str n &optional from-end)
  "取 STR 列宽不超 N 的子串（FROM-END 非 nil 从尾部取）。"
  (let ((chs (if from-end
                 (reverse (string-to-list str))
               (string-to-list str))))
    (cl-loop with w = 0
             for ch in chs
             for cw = (string-width (string ch))
             while (<= (+ w cw) n)
             do (cl-incf w cw) and collect ch into acc
             finally return (concat (if from-end (nreverse acc) acc)))))

(defun custom/dashboard--fit (label icon-w)
  "LABEL 超宽时中截，预留 ICON-W 与条目缩进（窄屏防折行）。"
  (let ((max (- (window-total-width) 6 icon-w)))
    (if (<= (string-width label) max)
        label
      (concat (custom/dashboard--take-width label (- max 10))
              "…"
              (custom/dashboard--take-width label 8 t)))))

;; ─── recents 条目：图标 + org 根相对路径 ────────────────────────────

(defun custom/dashboard--path-initials (path)
  "把 PATH 的目录部分缩成首字母。"
  (let* ((remote (or (file-remote-p path) ""))
         (local (or (file-remote-p path 'localname) path))
         (parts (split-string
                 (string-remove-prefix
                  "~/" (abbreviate-file-name (directory-file-name local)))
                 "/" t))
         (short
          (mapcar
           (lambda (part)
             (if (string-prefix-p "." part)
                 (let ((rest (string-remove-prefix "." part)))
                   (if (string-empty-p rest)
                       "."
                     (concat "." (substring rest 0 1))))
               (substring part 0 1)))
           parts)))
    (concat remote (string-join short "/"))))

(defun custom/dashboard--recent-label (path)
  "recents 条目文本：org 根下显示相对路径，其余目录首字母缩写。
（反映文件原名，不做标题替换。）"
  (let ((rel (and custom:org-directory
                  (file-in-directory-p path custom:org-directory)
                  (file-relative-name path custom:org-directory))))
    (cond
     ;; 上级回溯路径无信息量，直接用文件名
     ((string-prefix-p "../" rel) (file-name-nondirectory path))
     (rel (abbreviate-file-name rel))
     (t (format "%s/%s"
                (custom/dashboard--path-initials (file-name-directory path))
                (file-name-nondirectory path))))))

;; ─── 笔记段：文件夹内最近修改的文件 ─────────────────────────────────
;; 直接列目录（按 mtime），不经 org-roam db——首屏即出、零延迟。
;; 条目显示文件头 #+title:（时间戳文件名无信息量），缺失回退文件名。

(defun custom/dashboard--note-title (file)
  "笔记 FILE 头部 #+title: 的值，缺失或读取失败回退文件名。
只读首 4KB，N 个条目启动期一次性开销可忽略。"
  (or (ignore-errors
        (with-temp-buffer
          (insert-file-contents file nil 0 4096)
          (when (re-search-forward "^#\\+title:[ \t]*\\(.*\\)" nil t)
            (string-trim (match-string 1)))))
      (file-name-nondirectory file)))

(defun custom/dashboard--recent-roam-files (n)
  "笔记目录按 mtime 最近的 N 个 org 文件。
`directory-files-and-attributes' 一次 stat 全表（装饰排序，比较
纯内存）——sort 比较器内逐对 file-attributes 在 FUSE 存储上是
n·log(n) 次 stat 风暴。"
  (mapcar #'car
          (seq-take
           (sort (directory-files-and-attributes
                  custom:org-roam-directory t "\\.org\\'")
                 (lambda (a b)
                   (time-less-p
                    (file-attribute-modification-time (cdr b))
                    (file-attribute-modification-time (cdr a)))))
           n)))

(defun custom/dashboard--icon (code)
  "GUI 返回 NF 码点 CODE 的图标串，tty 返回空串。"
  (and (display-graphic-p)
       (propertize code 'face 'custom/dashboard-deco-icon)))

(defun custom/dashboard--file-icon (path)
  "按扩展名取 NF 文件图标（tty 返回空串）。"
  (or (custom/dashboard--icon
       (pcase (downcase (or (file-name-extension path) ""))
         ("org" "\uF0F6")
         ((or "md" "txt") "\uF15C")
         (_ "\uF15B")))
      ""))

;; ─── 条目段自绘：heading + 条目间空行 ───────────────────────────────

(defun custom/dashboard-insert-section* (heading icon files tag)
  "自绘段：HEADING + FILES 逐条 TAG 文本按钮，条目间空行。"
  (insert "\n")
  (dashboard-insert-heading heading nil icon)
  (if (null files)
      (insert "\n\n    "
              (propertize "暂无文件" 'face 'custom/dashboard-meta))
    (dolist (file files)
      (insert "\n\n    ")
      (widget-create 'item
                     :tag (funcall tag file)
                     :action `(lambda (&rest _) (find-file-existing ,file))
                     :button-face 'dashboard-items-face
                     :mouse-face 'highlight
                     :button-prefix "" :button-suffix ""
                     :format "%[%t%]")))
  (insert "\n"))

(defun custom/dashboard-insert-recents (list-size)
  "最近文件 LIST-SIZE 条：图标 + 路径标签（中截防窄屏折行）。"
  (unless recentf-mode (recentf-mode 1))
  (custom/dashboard-insert-section*
   "最近文件" (custom/dashboard--heading-icon "\uF017")
   (seq-take recentf-list list-size)
   (lambda (file)
     (let ((icon (custom/dashboard--file-icon file)))
       (concat icon (unless (string-empty-p icon) " ")
               (custom/dashboard--fit
                (custom/dashboard--recent-label file)
                (length icon)))))))

(defun custom/dashboard-insert-roam (list-size)
  "笔记文件夹按修改时间最近的 LIST-SIZE 个文件。"
  (custom/dashboard-insert-section*
   "最近笔记" (custom/dashboard--heading-icon "\uF02E")
   (custom/dashboard--recent-roam-files list-size)
   (lambda (file)
     (let ((icon (custom/dashboard--file-icon file)))
       (concat icon (unless (string-empty-p icon) " ")
               (custom/dashboard--fit (custom/dashboard--note-title file)
                                      (length icon)))))))

;; ─── navigator：[] 按钮 ─────────────────────────────────────────────

(defconst custom/dashboard--nav-buttons
  `((,(custom/glyph "\uF0E7" "") "抓笔记" "选择模板快速捕获"
     custom/capture-menu)
    (,(custom/glyph "\uF133" "") "议程" "本周日程"
     (lambda (&rest _)
       (require 'org-agenda)
       (custom/org--ensure-agenda-file)
       (org-agenda-list)))
    (,(custom/glyph "\uF07C" "") "笔记" "打开笔记文件夹"
     (lambda (&rest _)
       (custom/org--ensure-directories)
       (dired custom:org-roam-directory))))
  "按钮数据：(图标 标题 帮助 动作)。")

(defun custom/dashboard--nav-tag (icon title)
  "[] 按钮 tag：括号 dim、内文 bold；tty 无图标时内衬缩进对齐。"
  (concat (propertize "[" 'face 'custom/dashboard-deco)
          (propertize (if (string-empty-p icon)
                          (concat " " title " ")
                        (concat " " icon " " title " "))
                      'face 'custom/dashboard-button)
          (propertize "]" 'face 'custom/dashboard-deco)))

(defun custom/dashboard-insert-navigator ()
  "三枚 [] 按钮横排，整行居中。"
  (insert "\n")
  (let ((first t))
    (dolist (btn custom/dashboard--nav-buttons)
      (unless first (insert "  "))
      (setq first nil)
      (pcase-let ((`(,icon ,title ,help ,action) btn))
        (widget-create 'item
                       :tag (custom/dashboard--nav-tag icon title)
                       :help-echo help
                       :action action
                       :button-face 'dashboard-items-face
                       :mouse-face 'highlight
                       :button-prefix "" :button-suffix ""
                       :format "%[%t%]"))))
  (dashboard-center-text (line-beginning-position) (line-end-position))
  (insert "\n"))

;; ─── 抓笔记：触屏模板选择面板 ───────────────────────────────────────
;; org-mks（*Org Select*）以 `read-key-exclusive' 读键盘字符，tap 事件
;; 无法选中且每次触摸触发一轮重绘，触屏上不可用；改 widget 按钮直达。

(defvar custom/capture-menu-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'widget-button-click)
    (define-key map (kbd "<touchscreen-begin>") #'widget-button-click)
    map))

(define-derived-mode custom/capture-menu-mode special-mode "抓笔记"
  "触屏 capture 模板选择面板。"
  (setq-local touch-screen-display-keyboard nil))

(defun custom/capture--open (keys)
  "返回调 org-capture 模板 KEYS 的 widget action：当前窗显示并唤起键盘。"
  (lambda (&rest _)
    (require 'org-capture)
    ;; org 默认 split 显示 CAPTURE buffer，单窗机强制占当前窗
    (let ((display-buffer-overriding-action '((display-buffer-same-window))))
      (org-capture nil keys))
    (custom/touch-show-keyboard)))

(defun custom/capture-menu (&rest _)
  "打开触屏友好的抓笔记模板选择面板（条目取自 `org-capture-templates'）。"
  (interactive)
  (require 'org-capture)
  (switch-to-buffer (get-buffer-create "*抓笔记*"))
  (custom/capture-menu-mode)
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert (propertize "  选择抓笔记模板\n\n" 'face 'custom/dashboard-hero))
    ;; 过滤 :immediate-finish 隐藏模板（如剪贴板速存，无输入环节）
    (dolist (entry (seq-remove (lambda (e) (memq :immediate-finish e))
                               org-capture-templates))
      (widget-create 'item
                     :tag (concat " " (nth 1 entry) " ")
                     :action (custom/capture--open (car entry))
                     :button-face 'custom/dashboard-button
                     :mouse-face 'highlight
                     :button-prefix " "
                     :button-suffix " "
                     :format "%[%t%]")
      (insert "\n"))
    (goto-char (point-min))))

;; ─── 配置与启动 ─────────────────────────────────────────────────────

(defun custom/dashboard-insert-gap ()
  "footer 前空隙（与 items 尾部换行合计 2 空行）。"
  (insert "\n"))

;; 官方在每段前/末尾插 page-separator（默认换行），清空后段距由
;; items 前置换行 + generator 首尾换行精确控制（段间 2 空行）
(setq dashboard-page-separator "")

;; navigator 自绘（间距/括号样式直控）；hero 替换官方 banner/标题
(setq dashboard-startupify-list
      '(custom/dashboard-insert-hero
        custom/dashboard-insert-navigator
        dashboard-insert-items
        custom/dashboard-insert-gap
        dashboard-insert-footer))

(setq dashboard-center-content t
      dashboard-show-shortcuts nil            ; 触屏无键盘
      dashboard-set-heading-icons t
      dashboard-items '((recents . 4) (roam . 4)))

;; 名言池长度均 ≤34 列（含图标 footer 居中不折行）
(setq dashboard-footer-messages
      '("Learn Emacs once, use it forever."
        "Only Emacs can save your soul."
        "Lisp is a building material."
        "Everything is a buffer."
        "C-x M-c M-butterfly"
        "Org-mode is a way of life."
        "Real programmers count from zero."
        "Escape Meta Alt Control Shift"
        "Emacs is not just an editor."))

;; footer：随机名言 + 心形图标（tty 回退普通字符）
(setq dashboard-footer-icon
      (propertize (custom/glyph "\uF004" "♥")
                  'face 'custom/dashboard-deco-icon))

(setf (alist-get 'recents dashboard-item-generators)
      #'custom/dashboard-insert-recents)
(setf (alist-get 'roam dashboard-item-generators)
      #'custom/dashboard-insert-roam)

(dashboard-setup-startup-hook)

(provide 'init-dashboard)
;;; init-dashboard.el ends here
