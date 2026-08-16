;;; init-dashboard.el --- 启动仪表盘（dashboard + 触屏窄屏适配） -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; dashboard master 自带 Android 触屏修复（widget 点击走 mouse-1 与
;; <touchscreen-begin> 双通道），条目零改造可点。
;; 窄屏（约 40 列）适配：
;; · banner 用 braille 点阵（要求字体含盲文区，Maple 满足）
;; · 关键盘快捷键提示；agenda 前缀去掉 12 列 category 段
;; · recents 条目用「目录首字母 + 文件名」（官方 shorten-paths 是省略号
;;   截断，窄屏下不可读）
;; · 新增 roam item：最近修改的长期笔记（org-roam db 按 mtime 查询）
;; 在 init-org 之后加载（roam item 依赖 org-roam）。

;;; Code:

(straight-use-package 'dashboard)

(require 'dashboard)

;; ─── recents 条目：目录首字母缩写 ───────────────────────────────────

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

(defun custom/dashboard-insert-recents (list-size)
  "最近文件 LIST-SIZE 条，条目显示「目录首字母/文件名」
（官方默认省略号截断在窄屏下损失全部目录信息）。"
  (unless recentf-mode (recentf-mode 1))
  (dashboard-insert-section
   "Recent Files:"
   recentf-list
   list-size
   'recents
   nil                                  ; 触屏无键盘，不挂快捷键
   `(lambda (&rest _) (find-file-existing ,el))
   (format "%s/%s"
           (custom/dashboard--path-initials (file-name-directory el))
           (file-name-nondirectory el))))

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
                  ;; 反引号 vector：方括号字面量内 `,list-size' 才做运行时插值
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
       (format "%s" (car el))))))

(defun custom/dashboard-insert-agenda-deferred (list-size)
  "agenda 条目（冷启动跳过，见 `custom/dashboard--warm'）。"
  (when custom/dashboard--warm
    (dashboard-insert-agenda list-size)))

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
    (insert (propertize "选择抓笔记模板\n\n" 'face 'bold))
    (dolist (entry org-capture-templates)
      (widget-create 'item
                     :tag (nth 1 entry)
                     :action (custom/capture--open (car entry))
                     :button-face 'bold
                     :mouse-face 'highlight
                     :button-prefix "["
                     :button-suffix "]"
                     :format "%[%t%]")
      (insert "\n"))
    (goto-char (point-min))))

;; ─── 配置与启动 ─────────────────────────────────────────────────────

;; navigator 按钮行：icon 不走 display-icons-p 判断（navigator 直接显示
;; 给定字符串），tty 无 NF 字形故给空串只显文字；action 须 lambda 包装
;; （widget 调用带多余参数），命令则传符号；先 require 再调（capture
;; 模板挂在 with-eval-after-load 上，autoload 首次触发时可能先于模板执行）。
(setq dashboard-navigator-buttons
      `(((,(if (display-graphic-p) "\uF0E7" "") "抓笔记"
          "选择模板快速捕获"
          custom/capture-menu)
         (,(if (display-graphic-p) "\uF133" "") "议程"
          "本周日程"
          (lambda (&rest _)
            (require 'org-agenda)
            (custom/org--ensure-agenda-file)
            (org-agenda-list)))
         (,(if (display-graphic-p) "\uF0F6" "") "笔记"
          "打开笔记文件夹"
          (lambda (&rest _)
            (custom/org--ensure-directories)
            (dired custom:org-roam-directory))))))

;; navigator 不在默认 startupify 列表，显式加在标题后、条目前
(setq dashboard-startupify-list
      '(dashboard-insert-banner
        dashboard-insert-banner-title
        dashboard-insert-navigator
        dashboard-insert-init-info
        dashboard-insert-items
        dashboard-insert-footer))

(setq dashboard-startup-banner 'logo-braille
      dashboard-banner-logo-title "Welcome to Emacs!"
      dashboard-center-content t
      dashboard-show-shortcuts nil            ; 触屏无键盘
      dashboard-agenda-prefix-format "  %s "  ; 默认 %i %-12:c 在 40 列吃 14 列
      dashboard-items '((recents . 5) (agenda . 5) (roam . 5)))

(setf (alist-get 'recents dashboard-item-generators)
      #'custom/dashboard-insert-recents)
(setf (alist-get 'agenda dashboard-item-generators)
      #'custom/dashboard-insert-agenda-deferred)
(setf (alist-get 'roam dashboard-item-generators)
      #'custom/dashboard-insert-roam)

(dashboard-setup-startup-hook)

(provide 'init-dashboard)
;;; init-dashboard.el ends here
