;;; init-org.el --- Org 栈：capture（简化）/ agenda / roam -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 从桌面移植的简化版：基础编辑体验设置 + inbox/agenda/roam capture
;; 模板 + org-roam（sqlite3 CLI 后端，见下）+ org-appear / org-modern
;; 视觉现代化（GUI 下启用，tty 自动降级）。

;;; Code:

(defun custom/org--ensure-directories ()
  "确保 Org 相关目录存在。"
  (dolist (dir (list custom:org-directory
                     (expand-file-name "agenda" custom:org-directory)
                     custom:org-roam-directory))
    (unless (file-exists-p dir)
      (make-directory dir t))))

(defun custom/org--ensure-agenda-file ()
  "确保 agenda 目录下至少有一个 org 文件（空目录时 agenda 无内容可列）。"
  (custom/org--ensure-directories)
  (let ((dir (expand-file-name "agenda" custom:org-directory)))
    (unless (directory-files dir nil "\\`[^.#].*\\.org\\'")
      (with-temp-file (expand-file-name "index.org" dir)
        (insert "#+title: 议程\n\n* 任务\n")))))

(custom/org--ensure-agenda-file)

(use-package org
  :defer t
  ;; Emacs 30.2 内置 org 9.7 满足全部依赖（org-roam 要求 9.6+），禁用
  ;; straight 安装 git 版 org——其 build 缺 org-loaddefs.el 且与内置版
  ;; 并存时版本错乱（Org version mismatch）
  :straight nil
  :custom
  (org-directory custom:org-directory)
  (org-agenda-files (list (expand-file-name "agenda" custom:org-directory)))
  (org-agenda-window-setup 'current-window)  ; 手机单窗口
  (org-hide-emphasis-markers t)
  (org-startup-indented t)
  (org-hide-leading-stars t)
  (org-ellipsis "...")
  (org-auto-align-tags nil)
  (org-tags-column 0)
  (org-catch-invisible-edits 'show-and-error)
  (org-special-ctrl-a/e t)
  (org-insert-heading-respect-content t)
  (org-pretty-entities t)
  (org-use-sub-superscripts '{})
  (org-cycle-separator-lines 2)
  (org-startup-folded 'overview)
  (org-blank-before-new-entry '((heading . t) (plain-list-item . auto)))
  (org-fontify-whole-heading-line t)
  (org-fontify-done-headline t)
  (org-fontify-quote-and-verse-blocks t)
  (org-src-fontify-natively t)
  (org-src-tab-acts-natively t)
  (org-src-preserve-indentation t)
  (org-src-window-setup 'current-window)  ; 手机单窗口
  (org-edit-src-content-indentation 0)
  (org-image-actual-width '(300)))  ; 内联图片显示宽度（px），真机可调

;; ─── capture：inbox / agenda / roam（模板从桌面移植） ───────────────

(defvar custom/org-capture--roam-title nil
  "本次 Roam capture 的标题。")

(defvar org-capture-templates nil)  ; org-capture.el（模板在其加载后设置）
(declare-function org-agenda-files "org-agenda")
(declare-function custom/touch-show-keyboard "init-touch")

(defun custom/org-capture--agenda-file ()
  "返回本次 capture 的目标 agenda 文件（取 `org-agenda-files' 首项）。"
  (custom/org--ensure-directories)
  (car (org-agenda-files)))

(defun custom/org-capture--roam-file ()
  "返回本次长期笔记的 Roam 文件路径。"
  (custom/org--ensure-directories)
  (custom/touch-show-keyboard)
  (setq custom/org-capture--roam-title (read-string "长期笔记标题: "))
  (expand-file-name
   (format "%s.org" (format-time-string "%Y%m%d-%H%M%S"))
   custom:org-roam-directory))

(defun custom/org-capture--roam-title-value ()
  "返回当前 Roam capture 标题。"
  (or custom/org-capture--roam-title "未命名笔记"))

(defun custom/org-capture--clear-state ()
  "`org-capture-after-finalize-hook' 回调：清理本次 capture 的临时状态。"
  (setq custom/org-capture--roam-title nil))

(with-eval-after-load 'org-capture
  (setq org-capture-templates
        `(("ki" "Inbox 草稿" entry
           (file ,custom:org-inbox-file)
           "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%i\n")
          ("kt" "任务 (agenda)" entry
           (file custom/org-capture--agenda-file)
           "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%i\n")
          ("kd" "带日期任务 (agenda)" entry
           (file custom/org-capture--agenda-file)
           "* TODO %?\nSCHEDULED: %^t\n:PROPERTIES:\n:CREATED: %U\n:END:\n%i\n")
          ("ke" "日程事件 (agenda)" entry
           (file custom/org-capture--agenda-file)
           "* %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%i\n")
          ("kr" "Roam 长期笔记" plain
           (file custom/org-capture--roam-file)
           "#+title: %(custom/org-capture--roam-title-value)\n:PROPERTIES:\n:ID:       %(org-id-new)\n:CREATED:  %U\n:END:\n\n%?")))
  (add-hook 'org-capture-after-finalize-hook
            #'custom/org-capture--clear-state))

;; ─── org-roam（sqlite3 CLI 后端，db 各端独立重建） ──────────────────
;; Android 官方 APK 无内置 sqlite（(featurep 'sqlite3) = nil），org-roam
;; 2.3+ 的 emacsql 内置后端不可用 → pin 2.2.2 + emacsql 3.1.1（sqlite3
;; CLI 后端仅存于 emacsql 3.x），走 Termux 的 sqlite3（缺失则跳过）。
;; 已知代价：每查询 spawn 进程（官方标注 BROKEN，#1927 缓存 bug）。

(let ((sqlite3 (executable-find "sqlite3")))
  (if (not sqlite3)
      (display-warning 'init-org
                       "sqlite3 CLI 不可用，org-roam 未启用（Termux: pkg install sqlite3）")
    (use-package emacsql)
    ;; connector 是运行时选择，org-roam 声明依赖里没有 emacsql-sqlite3，
    ;; 须显式安装
    (use-package emacsql-sqlite3)
    (use-package org-roam
      :defer t
      :commands (org-roam-node-find org-roam-node-insert org-roam-buffer-toggle)
      :init
      ;; 清残留 sqlite3 子进程：Emacs 被系统杀掉时子进程成孤儿，独占
      ;; org-roam.db 文件锁，新连接打开同一 db 时阻塞直至 emacsql-wait
      ;; 超时（30s）。pkill -f 按 db 完整路径匹配，不影响其它 sqlite3。
      (call-process "pkill" nil nil nil "-f"
                    (expand-file-name ".cache/emacs/org-roam.db"
                                      custom:data-home))
      (setq org-roam-database-connector 'sqlite3)
      :custom
      (org-roam-directory custom:org-roam-directory)
      ;; db 放缓存区，不随 Syncthing 同步（各端独立重建）
      (org-roam-db-location
       (expand-file-name ".cache/emacs/org-roam.db" custom:data-home))
      (org-roam-completion-everywhere nil)
      :config
      (org-roam-db-autosync-mode))))

;; ─── org-roam 数据访问接口（展示层唯一入口） ─────────────────────────
;; 查询 + 增量同步 + 错误降级集中于此：org-roam schema/版本变更只改本
;; 模块，dashboard 等展示层不接触 org-roam 符号。

(declare-function org-roam-db-query "org-roam")
(declare-function org-roam-db-sync "org-roam")

(defun custom/org-roam-recent-notes (n)
  "最近修改的 N 条 Roam 笔记，返回 ((标题 . 文件) ...) 列表。
拉取前显式增量同步（autosync 不索引外部新到文件，Syncthing 场景）；
org-roam 不可用或查询失败时返回 nil，调用方按空数据降级。"
  (ignore-errors
    (require 'org-roam)
    (org-roam-db-sync)
    (mapcar (lambda (row)
              (cons (or (nth 0 row)
                        (file-name-nondirectory (nth 1 row)))
                    (nth 1 row)))
            (org-roam-db-query
             `[:select [nodes:title nodes:file]
               :from nodes
               :join files :on (= nodes:file files:file)
               :order-by (desc files:mtime)
               :limit ,n]))))

;; ─── org-appear + org-modern（org-appear 纯 face 变换，Android 字体可用；
;; org-modern 需 Nerd 字形，主字体 Maple 含字形，GUI 下启用） ─────────

(use-package org-appear
  :hook (org-mode . org-appear-mode)
  :custom
  (org-appear-autoemphasis t)
  (org-appear-autolinks t)
  (org-appear-autosubmarkers t)
  (org-appear-autoentities t))

;; org-modern 的星号替换与表格竖线都是 font-lock 内联 display/face 规格，
;; 在 tty 上会渲染成白底/反色块（Android 终端无颜色管理），tty 下降级为
;; ASCII 表格与 Unicode 子弹，前导星号交 org-indent 隐藏
(defun custom/org-modern--apply-display ()
  "非 GUI frame 下降级 `org-modern' 的星号与表格渲染。"
  (unless (display-graphic-p)
    (setq-local org-modern-table nil
                org-modern-table-vertical nil
                org-modern-table-horizontal nil
                org-modern-star 'replace
                org-modern-hide-stars 'leading)))

(add-hook 'org-mode-hook #'custom/org-modern--apply-display -90)

(use-package org-modern
  :hook (org-mode . org-modern-mode)
  :custom
  (org-modern-star 'replace)
  (org-modern-replace-stars '("" "" "󰜋" "󰜌" "" "" ""))
  (org-modern-list
   '((?- . "")
     (?* . "")
     (?+ . "")))
  (org-modern-hide-stars 'leading)
  (org-modern-table t)
  (org-modern-table-vertical 2)
  (org-modern-table-horizontal 0.12)
  (org-modern-keyword t)
  (org-modern-todo t)
  (org-modern-tag t)
  (org-modern-block-name t)
  (org-modern-block-fringe 4))

(provide 'init-org)
;;; init-org.el ends here
