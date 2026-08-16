;;; init-dashboard.el --- 启动仪表盘（触屏窄屏视觉体系） -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; dashboard master 自带 Android 触屏修复（widget 点击走 mouse-1 与
;; <touchscreen-begin> 双通道），条目零改造可点。
;; 窄屏（约 40 列）视觉体系：
;; · hero 区：对称装饰线 + 大标题（NF 图标）+ 副标题，替换官方 braille
;;   大 logo（手机半屏高，内容被挤出首屏）
;; · navigator 三枚胶囊按钮（圆角括号 + 内衬空白扩大点按面）
;; · 各段 heading 短装饰线 + NF 图标夹标题，随内容居中
;; · recents 条目 = 文件图标 + org 根相对路径（其余目录首字母缩写）
;; · 无 NF 字形环境（tty）自动降级纯文本

;;; Code:

(straight-use-package 'dashboard)

(require 'dashboard)

;; ─── faces：官方默认继承偏艳，窄屏调和 ─────────────────────────────

(defface custom/dashboard-hero
  '((t :inherit dashboard-banner-logo-title :weight bold :height 1.5))
  "仪表盘大标题。" :group 'emacs-mobile)

(defface custom/dashboard-subtitle
  '((t :inherit font-lock-doc-face :height 0.9))
  "仪表盘副标题。" :group 'emacs-mobile)

(defface custom/dashboard-deco
  '((t :inherit shadow))
  "装饰线（hero 分隔线、heading 两侧细线）。" :group 'emacs-mobile)

(defface custom/dashboard-deco-icon
  '((t :inherit font-lock-keyword-face))
  "装饰线/条目中的 NF 图标。" :group 'emacs-mobile)

(defface custom/dashboard-meta
  '((t :inherit shadow))
  "启动信息行。" :group 'emacs-mobile)

(defface custom/dashboard-button
  '((t :weight bold))
  "navigator 胶囊按钮文字。" :group 'emacs-mobile)

;; ─── 通用装饰 ───────────────────────────────────────────────────────

;; ─── NF 图标码点（GUI 直出字形，tty 无字形返回空串） ────────────────

(defun custom/dashboard--icon (code)
  "GUI 返回 NF 码点 CODE 的图标串，tty 返回空串。"
  (and (display-graphic-p)
       (propertize code 'face 'custom/dashboard-deco-icon)))

(defun custom/dashboard--rule (&optional icon)
  "对称装饰分隔线：细线 + ICON + 细线。"
  (let ((dash (propertize (make-string 9 ?─) 'face 'custom/dashboard-deco)))
    (concat dash
            (propertize (if icon (concat " " icon " ") " ")
                        'face 'custom/dashboard-deco-icon)
            dash)))

(defun custom/dashboard-insert-hero ()
  "hero 区：分隔线 + 大标题 + 副标题（替换官方 braille logo）。"
  (insert "\n")
  (dashboard-insert-center (custom/dashboard--rule (custom/dashboard--icon "\u2726")))
  (insert "\n")
  (dashboard-insert-center
   (propertize
    (concat (when-let* ((icon (custom/dashboard--icon "\uE632")))
              (concat icon " "))
            "Emacs")
    'face 'custom/dashboard-hero))
  (insert "\n")
  (dashboard-insert-center
   (propertize "The one true editor" 'face 'custom/dashboard-subtitle))
  (insert "\n")
  (dashboard-insert-center (custom/dashboard--rule (custom/dashboard--icon "\u2726")))
  (insert "\n"))

;; ─── heading：NF 图标 + 两侧短装饰线 ────────────────────────────────
;; heading 文本经 `dashboard-item-names' overlay 换显示名（buffer 内保留
;; 英文原文，`dashboard--current-section' 段导航仍按原文识别）。

(setq dashboard-item-names
      '(("Recent Files:" . "最近文件")
        ("Agenda for the coming week:" . "本周议程")
        ("Agenda for today:" . "今日议程")
        ("Recent Roam Notes:" . "最近笔记")))

(defun custom/dashboard--heading-icon (code &rest _)
  "返回码点 CODE 的图标串（忽略 dashboard 传入的图标尺寸参数）。"
  (propertize code 'face 'custom/dashboard-deco-icon))

;; 列表值走自定义函数直出 NF 字形，不依赖 octicon/nerd-icons 包
(setq dashboard-set-heading-icons t
      dashboard-heading-icons
      `((recents . (custom/dashboard--heading-icon "\uF017"))
        (agenda  . (custom/dashboard--heading-icon "\uF133"))
        (roam    . (custom/dashboard--heading-icon "\uF02E"))))

(defun custom/dashboard-insert-heading-deco (fn heading &optional shortcut icon)
  "HEADING 两侧加短装饰线（整行居中由 `dashboard-center-content' 统一做）。"
  (prog1 (funcall fn heading shortcut icon)
    (let ((deco (propertize "──── " 'face 'custom/dashboard-deco)))
      (save-excursion
        ;; overlay display 不改变 buffer 文本，回退按原文长度；
        ;; icon 回退须与官方插入条件一致（tty 无字形不插入 icon）
        (goto-char (- (point) (length heading)))
        (when (and (dashboard-display-icons-p) dashboard-set-heading-icons icon)
          (goto-char (- (point) (1+ (length icon)))))
        (insert deco))
      (insert (propertize " ────" 'face 'custom/dashboard-deco)))))

(advice-add #'dashboard-insert-heading :around
            #'custom/dashboard-insert-heading-deco)

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
  "recents 条目文本：org 根下显示相对路径，其余目录首字母缩写。"
  (let ((rel (and (boundp 'custom:org-directory)
                  custom:org-directory
                  (file-in-directory-p path custom:org-directory)
                  (file-relative-name path custom:org-directory))))
    (cond
     ;; 上级回溯路径无信息量，直接用文件名
     ((string-prefix-p "../" rel) (file-name-nondirectory path))
     (rel (abbreviate-file-name rel))
     (t (format "%s/%s"
                (custom/dashboard--path-initials (file-name-directory path))
                (file-name-nondirectory path))))))

(defun custom/dashboard--file-icon (path)
  "按扩展名取 NF 文件图标（tty 返回空串）。"
  (or (custom/dashboard--icon
       (pcase (downcase (or (file-name-extension path) ""))
         ("org" "\uF0F6")
         ((or "md" "txt") "\uF15C")
         (_ "\uF15B")))
      ""))

(defun custom/dashboard-insert-recents (list-size)
  "最近文件 LIST-SIZE 条：图标 + 路径标签（省略号截断窄屏不可读）。"
  (unless recentf-mode (recentf-mode 1))
  (dashboard-insert-section
   "Recent Files:"
   recentf-list
   list-size
   'recents
   nil                                  ; 触屏无键盘，不挂快捷键
   `(lambda (&rest _) (find-file-existing ,el))
   (let ((icon (custom/dashboard--file-icon el)))
     (concat icon (unless (string-empty-p icon) " ")
             (custom/dashboard--fit
              (custom/dashboard--recent-label el)
              (length icon))))))

;; ─── agenda/roam 延迟填充 ───────────────────────────────────────────
;; 两段生成要拉起 org-agenda/org-roam 全家（约占启动大头），冷启动首屏
;; 跳过，进入空闲后补齐刷新（recentf/banner 不受影响，首屏即有）。

(defvar custom/dashboard--warm nil
  "t 时 agenda/roam 段直接生成（首屏后的补齐刷新）。")

;; ─── roam 条目：最近修改的长期笔记 ──────────────────────────────────

(declare-function org-roam-db-query "org-roam")
(declare-function org-roam-db-sync "org-roam")
(declare-function custom/touch-show-keyboard "init-touch")
(defvar org-capture-templates)

(defun custom/dashboard-insert-roam (list-size)
  "最近修改的 Roam 笔记 LIST-SIZE 条；db 不可用时整块降级为 No items。"
  (when custom/dashboard--warm
    (let* ((rows (ignore-errors
                  (require 'org-roam)
                  ;; 显式增量同步：autosync 不索引外部新到文件（Syncthing 场景）
                  (org-roam-db-sync)
                  (org-roam-db-query
                   `[:select [nodes:title nodes:file]
                     :from nodes
                     :join files :on (= nodes:file files:file)
                     :order-by (desc files:mtime)
                     :limit ,list-size])))
           (items (mapcar (lambda (row)
                            (cons (or (nth 0 row)
                                      (file-name-nondirectory (nth 1 row)))
                                  (nth 1 row)))
                          rows)))
      (dashboard-insert-section
       "Recent Roam Notes:"
       items
       list-size
       'roam nil
       `(lambda (&rest _) (find-file-existing ,(cdr el)))
       (let ((icon (or (custom/dashboard--icon "\uF02E") "")))
         (concat icon (unless (string-empty-p icon) " ")
                 (custom/dashboard--fit (car el) (length icon))))))))

(defun custom/dashboard-insert-agenda-deferred (list-size)
  "agenda 条目（冷启动跳过，见 `custom/dashboard--warm'）。"
  (when custom/dashboard--warm
    (dashboard-insert-agenda list-size)))

(defun custom/dashboard--agenda-fit (items)
  "agenda 条目串超宽时中截（窄屏防折行；substring 保留定位属性）。"
  (mapcar (lambda (s) (custom/dashboard--fit s 6)) items))

(advice-add #'dashboard-agenda--sorted-agenda :filter-return
            #'custom/dashboard--agenda-fit)

(defun custom/dashboard--warm-fill ()
  "补齐 agenda/roam 段并刷新仪表盘（空闲触发，不抢焦点）。"
  (setq custom/dashboard--warm t)
  (let ((buf (get-buffer dashboard-buffer-name)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (dashboard-insert-startupify-lists t)))))

(run-with-idle-timer 4 nil #'custom/dashboard--warm-fill)

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
    (dolist (entry org-capture-templates)
      (widget-create 'item
                     :tag (concat " " (nth 1 entry) " ")
                     :action (custom/capture--open (car entry))
                     :button-face 'custom/dashboard-button
                     :mouse-face 'highlight
                     :button-prefix "╭─ "
                     :button-suffix " ─╯"
                     :format "%[%t%]")
      (insert "\n"))
    (goto-char (point-min))))

;; ─── 配置与启动 ─────────────────────────────────────────────────────

;; navigator 胶囊按钮：圆角括号 + 内衬空白扩大点按面；icon 不走
;; display-icons-p 判断（navigator 直接显示给定字符串），tty 无 NF
;; 字形故给空串只显文字；action 须 lambda 包装（widget 调用带多余
;; 参数）；先 require 再调（capture 模板挂在 with-eval-after-load 上，
;; autoload 首次触发时可能先于模板执行）。
(setq dashboard-navigator-buttons
      `(((,(if (display-graphic-p) "\uF0E7" "") " 抓笔记 "
          "选择模板快速捕获"
          custom/capture-menu custom/dashboard-button "╭" "╯")
         (,(if (display-graphic-p) "\uF133" "") " 议程 "
          "本周日程"
          (lambda (&rest _)
            (require 'org-agenda)
            (custom/org--ensure-agenda-file)
            (org-agenda-list))
          custom/dashboard-button "╭" "╯")
         (,(if (display-graphic-p) "\uF07C" "") " 笔记 "
          "打开笔记文件夹"
          (lambda (&rest _)
            (custom/org--ensure-directories)
            (dired custom:org-roam-directory))
          custom/dashboard-button "╭" "╯"))))

;; navigator 不在默认 startupify 列表；hero 替换官方 banner/标题
(setq dashboard-startupify-list
      '(custom/dashboard-insert-hero
        dashboard-insert-navigator
        custom/dashboard-insert-init-info
        dashboard-insert-items
        dashboard-insert-footer))

(defun custom/dashboard-insert-init-info ()
  "启动信息行：图标 + 包数 + 秒数（短格式，窄屏不折行）。"
  (dashboard-insert-center
   (propertize
    (format "%s%d 包 · %.2fs 启动"
            (or (custom/dashboard--icon "\uF0E7") "")
            (dashboard-init--packages-count)
            (string-to-number (emacs-init-time)))
    'face 'custom/dashboard-meta)))

(setq dashboard-center-content t
      dashboard-show-shortcuts nil            ; 触屏无键盘
      dashboard-agenda-prefix-format "  %s "  ; 默认 %i %-12:c 在 40 列吃 14 列
      dashboard-items '((recents . 5) (agenda . 5) (roam . 5)))

;; footer：固定标语 + 心形图标
(setq dashboard-footer-messages '("The one true editor, Emacs!")
      dashboard-footer-icon
      (propertize (if (display-graphic-p) "\uF004" "♥")
                  'face 'custom/dashboard-deco-icon))

(setf (alist-get 'recents dashboard-item-generators)
      #'custom/dashboard-insert-recents)
(setf (alist-get 'agenda dashboard-item-generators)
      #'custom/dashboard-insert-agenda-deferred)
(setf (alist-get 'roam dashboard-item-generators)
      #'custom/dashboard-insert-roam)

(dashboard-setup-startup-hook)

(provide 'init-dashboard)
;;; init-dashboard.el ends here
