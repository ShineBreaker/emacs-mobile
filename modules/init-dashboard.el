;;; init-dashboard.el --- 启动仪表盘（dashboard + 触屏窄屏适配） -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; dashboard master 自带 Emacs Android 触屏修复（widget 点击走 mouse-1
;; 与 <touchscreen-begin> 双通道，PR #567），条目零改造可点。
;; 窄屏（约 40 列）适配：
;; · banner 用 braille 点阵（30 列；官方注释要求字体含盲文区，Maple 满足）
;; · 关键盘快捷键提示（触屏无键盘）；agenda 前缀去掉 12 列 category 段
;; · recents 条目用「目录首字母 + 文件名」（桌面配置 path-initials 方案
;;   移植）——官方 shorten-paths 是省略号截断，窄屏下不可读
;; · 新增 roam item：最近修改的长期笔记（org-roam db 按 mtime 查询）
;; require 顺序：init-org 之后（roam item 依赖 org-roam）。

;;; Code:

(straight-use-package 'dashboard)

(require 'dashboard)

;; ─── recents 条目：目录首字母缩写 ───────────────────────────────────

(defun custom/dashboard--path-initials (path)
  "把 PATH 的目录部分缩成首字母（从桌面配置移植）。"
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
  "最近文件 LIST-SIZE 条，条目显示「目录首字母/文件名」。
覆盖官方 generator：默认的省略号截断在窄屏下损失全部目录信息。"
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

;; ─── roam 条目：最近修改的长期笔记 ──────────────────────────────────

(declare-function org-roam-db-query "org-roam")
(declare-function org-roam-db-sync "org-roam")

(defun custom/dashboard-insert-roam (list-size)
  "最近修改的 Roam 笔记 LIST-SIZE 条。
db 不可用（sqlite3 CLI 缺失 / init-org 未启用 org-roam / 目录为空）
时整块静默降级为 No items。"
  (let* ((rows (ignore-errors
                (require 'org-roam)
                ;; 显式增量同步：autosync 不索引外部新到文件（Syncthing
                ;; 场景），不同步则 db 过时、条目缺失
                (org-roam-db-sync)
                ;; 反引号 vector：emacsql 方括号字面量内 `,list-size'
                ;; 才做运行时插值（普通 vector 会把符号按字面编译）
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
     (format "%s" (car el)))))

;; ─── 配置与启动 ─────────────────────────────────────────────────────

;; navigator 按钮行：org/笔记入口从工具栏迁来（2026-08-15 拍板）。
;; icon 不走 display-icons-p 判断（navigator 直接显示给定字符串），
;; tty 无 NF 字形故给空串只显文字；action 须 lambda 包装（widget 调用
;; 带多余参数，直接绑命令 symbol 会 wrong-number-of-arguments）；
;; 先 require 再调——capture 的模板挂在 with-eval-after-load 上，
;; autoload 首次触发时函数体可能先于模板设置执行（实测弹 customize）。
(setq dashboard-navigator-buttons
      `(((,(if (display-graphic-p) "\uF0E7" "") "抓笔记"
          "快速捕获"
          (lambda (&rest _) (require 'org-capture) (org-capture)))
         (,(if (display-graphic-p) "\uF133" "") "议程"
          "本周日程"
          (lambda (&rest _) (require 'org-agenda) (org-agenda)))
         (,(if (display-graphic-p) "\uF0C1" "") "Roam 笔记"
          "查找/新建长期笔记"
          (lambda (&rest _) (org-roam-node-find))))))

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
(setf (alist-get 'roam dashboard-item-generators)
      #'custom/dashboard-insert-roam)

(dashboard-setup-startup-hook)

(provide 'init-dashboard)
;;; init-dashboard.el ends here
