;;; init-org.el --- Org 栈：capture（简化）/ agenda / roam -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 从桌面移植的简化版：基础编辑体验设置 + inbox/agenda/roam capture
;; 模板 + org-roam（sqlite3 CLI 后端，见下）。
;; 不装 org-modern：Android sfnt 字体后端不支持其 Nerd 字形。

;;; Code:

(defun custom/org--ensure-directories ()
  "确保 Org 相关目录存在。"
  (dolist (dir (list custom:org-directory
                     (expand-file-name "agenda" custom:org-directory)
                     custom:org-roam-directory))
    (unless (file-exists-p dir)
      (make-directory dir t))))

(use-package org
  :defer t
  :custom
  (org-directory custom:org-directory)
  (org-agenda-files (list (expand-file-name "agenda" custom:org-directory)))
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

(defun custom/org-capture--agenda-file ()
  "返回本次 capture 的目标 agenda 文件（取 `org-agenda-files' 首项）。"
  (custom/org--ensure-directories)
  (car (org-agenda-files)))

(defun custom/org-capture--roam-file ()
  "返回本次长期笔记的 Roam 文件路径。"
  (custom/org--ensure-directories)
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
      ;; db-autosync 启动即访问 roam 目录，先确保存在
      (custom/org--ensure-directories)
      (setq org-roam-database-connector 'sqlite3)
      :custom
      (org-roam-directory custom:org-roam-directory)
      ;; db 放缓存区，不随 Syncthing 同步（各端独立重建）
      (org-roam-db-location
       (expand-file-name ".cache/emacs/org-roam.db" custom:data-home))
      (org-roam-completion-everywhere nil)
      :config
      (org-roam-db-autosync-mode))))

;; ─── org-appear（纯 face 变换，Android 字体可用） ───────────────────

(use-package org-appear
  :hook (org-mode . org-appear-mode)
  :custom
  (org-appear-autoemphasis t)
  (org-appear-autolinks t)
  (org-appear-autosubmarkers t)
  (org-appear-autoentities t))

(provide 'init-org)
;;; init-org.el ends here
