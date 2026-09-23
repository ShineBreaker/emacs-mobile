;;; init-org.el --- Org 栈：capture（简化）/ agenda / roam -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 从桌面移植的简化版：基础编辑体验设置 + inbox/agenda/roam capture
;; 模板 + org-roam（sqlite3 CLI 后端，见下）+ org-appear / org-modern
;; 视觉现代化（GUI 下启用，tty 自动降级）。

;;; Code:

(declare-function org-roam-file-p "org-roam")
(declare-function org-roam-db-update-file "org-roam")

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

;; 推迟到空闲：org 根在 FUSE 共享存储上，启动期同步 stat/列目录会阻塞首屏；
;; 议程与 capture 入口各自已调用 ensure，用户抢先操作也不缺目录
(run-with-idle-timer 1 nil #'custom/org--ensure-agenda-file)

(use-package org
  :defer t
  ;; Emacs 31.1 内置 org 9.8 满足全部依赖（org-roam 要求 9.6+），禁用
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
           "#+title: %(custom/org-capture--roam-title-value)\n:PROPERTIES:\n:ID:       %(org-id-new)\n:CREATED:  %U\n:END:\n\n%?")
         ;; 隐藏模板（抓笔记面板过滤）：不弹 buffer 不等输入，直接完成
          ("kq" "剪贴板速存" entry
           (file ,custom:org-inbox-file)
           "* %(custom/org-capture--clip-heading)\n:PROPERTIES:\n:CREATED: %U\n:END:\n%(custom/org-capture--clip-body)\n"
           :prepend t :immediate-finish t)
          ;; org-protocol 分享入库：描述/链接/正文由协议参数填充
          ("kp" "协议分享" entry
           (file ,custom:org-inbox-file)
           "* %(custom/org-capture--protocol-heading)\n:PROPERTIES:\n:CREATED: %U\n:END:\n%:link\n\n%:initial\n"
           :prepend t :immediate-finish t)))
  (add-hook 'org-capture-after-finalize-hook
            #'custom/org-capture--clear-state))

;; ─── 剪贴板速存：一键入库（tool-bar「速」钮），不弹模板面板 ────────

(defvar custom/org-capture--clip-text nil
  "本次速存的剪贴板内容（模板函数在动态作用域内读取）。")

(defun custom/clipboard-content ()
  "系统剪贴板文本（GUI selection 不可用时回退 kill-ring 头）。"
  (or (ignore-errors (gui-get-selection 'CLIPBOARD 'STRING))
      (car kill-ring)))

(defun custom/org-capture--clip-heading ()
  "速存条目标题：剪贴板首个非空行截 30 列。"
  (let* ((text (string-trim (or custom/org-capture--clip-text "")))
         (head (truncate-string-to-width
                (or (car (split-string text "[\r\n]+")) "")
                30 nil nil "…")))
    (if (string-empty-p head) "（剪贴板内容）" head)))

(defun custom/org-capture--clip-body ()
  "速存条目正文：剪贴板全文。"
  (or custom/org-capture--clip-text ""))

(defun custom/inbox-quick-capture ()
  "剪贴板一键速存为 inbox TODO 条目。"
  (interactive)
  (let ((clip (custom/clipboard-content)))
    (if (or (null clip) (string-empty-p (string-trim clip)))
        (message "剪贴板为空，未速存")
      (require 'org-capture)
      (let ((custom/org-capture--clip-text clip))
        (org-capture nil "kq")
        (message "已速存：%s" (custom/org-capture--clip-heading))))))

;; ─── org-protocol：其他 App 分享入库（org-protocol://capture） ─────
;; Android 端口把 emacsclient wrapper 注册为 org-protocol handler，
;; 链接经 server-visit-files 转交 org-protocol-capture（server 见
;; init-misc.el）。默认模板必须显式指定：nil 会让 org-capture 弹
;; org-mks *Org Select* 键盘面板，触屏不可选（见 init-dashboard.el）。

(declare-function org-capture-get "org-capture")
(defvar org-protocol-default-template-key)

(defun custom/org-capture--protocol-heading ()
  "协议分享条目标题：链接描述为空时取正文首行截 30 列。"
  (let ((desc (org-capture-get :description)))
    (if (and desc (not (string-empty-p (string-trim desc))))
        desc
      (let ((head (truncate-string-to-width
                   (or (car (split-string
                             (or (org-capture-get :initial) "") "[\r\n]+"))
                       "")
                   30 nil nil "…")))
        (if (string-empty-p (string-trim head)) "（分享内容）" head)))))

(when custom:android-p
  ;; 空闲加载不占启动；server 侧 advice 在 require 后即刻生效
  (run-with-idle-timer
   5 nil (lambda ()
           (require 'org-protocol)
           (setq org-protocol-default-template-key "kp"))))

;; ─── org-roam（sqlite3 CLI 后端，db 各端独立重建） ──────────────────
;; Android 官方 APK 无内置 sqlite（(featurep 'sqlite3) = nil），org-roam
;; 2.3+ 的 emacsql 内置后端不可用 → pin 2.2.2 + emacsql 3.1.1（sqlite3
;; CLI 后端仅存于 emacsql 3.x），走 Termux 的 sqlite3（缺失则跳过）。
;; 已知代价：常驻 sqlite3 CLI 子进程，每条语句经管道往返同步等待（建立
;; 连接时 make-process 一次，之后复用）；官方将该后端标为 BROKEN（#1927 缓存 bug）。

(defcustom custom/org-roam-defer-threshold (* 100 1024)
  "超过此字节数的 org-roam 文件改为延迟合并索引。
索引要全文 parse（227KB 桌面实测 0.4s，真机数倍），放在保存路径会卡输入。"
  :type 'integer
  :group 'emacs-mobile)

(defvar custom/org-roam--pending nil
  "保存后待索引的大文件（合并连续保存，避免每次都同步 parse 全文）。")
(defvar custom/org-roam--flush-timer nil
  "待索引刷新计时器（去重用；idle 与绝对计时两条路都调 flush）。")

(defun custom/org-roam-update-on-save ()
  "保存 org-roam 文件后增量更新索引。
小文件立即更新保持即时性；大文件（超 `custom/org-roam-defer-threshold'）
只记入待办，由 `custom/org-roam-flush-pending' 择机合并刷新。"
  (when (org-roam-file-p (buffer-file-name))
    (if (< (buffer-size) custom/org-roam-defer-threshold)
        (with-demoted-errors "org-roam 索引更新失败: %S"
          (org-roam-db-update-file))
      (add-to-list 'custom/org-roam--pending (buffer-file-name))
      (unless (timerp custom/org-roam--flush-timer)
        ;; idle 优先（用户停手后才做重活）；绝对计时兜底——Android 功耗
        ;; 管理下 idle timer 疑不触发
        (setq custom/org-roam--flush-timer
              (run-with-idle-timer 3 nil #'custom/org-roam-flush-pending))
        (run-with-timer 15 nil #'custom/org-roam-flush-pending)))))

(defun custom/org-roam-flush-pending ()
  "把待索引文件写进 org-roam db（幂等，可被 idle/绝对计时/退出钩子调用）。"
  (when (timerp custom/org-roam--flush-timer)
    (cancel-timer custom/org-roam--flush-timer)
    (setq custom/org-roam--flush-timer nil))
  (let ((files (prog1 (nreverse custom/org-roam--pending)
                 (setq custom/org-roam--pending nil))))
    (when files
      (with-demoted-errors "org-roam 索引更新失败: %S"
        (dolist (f files)
          (when (file-exists-p f)
            (org-roam-db-update-file f)))))))

(add-hook 'kill-emacs-hook #'custom/org-roam-flush-pending)

(let ((sqlite3 (executable-find "sqlite3")))
  (if (not sqlite3)
      (display-warning 'init-org
                       "sqlite3 CLI 不可用，org-roam 未启用（Termux: pkg install sqlite3）")
    ;; emacsql / emacsql-sqlite3 均延迟：org-roam-db 建立连接时自行
    ;; `(require 'emacsql-sqlite3)'（org-roam-db--conn-fn，按 connector
    ;; 分支加载），启动期只需超时值就位（defvar 变量，先设再加载）
    (use-package emacsql
      :defer t
      :init
      ;; 3s：db 被残留进程锁住时查询快速失败降级，默认 30s 在触屏上无法中断
      (setq emacsql-global-timeout 3))
    ;; connector 是运行时选择，org-roam 声明依赖里没有 emacsql-sqlite3，
    ;; 须显式安装（延迟加载，保证 straight 装包即可）
    (use-package emacsql-sqlite3
      :defer t)
    ;; magit-section 的 transient 需求由内置满足（31.1 起 0.13.5）
    (use-package org-roam
      :defer t
      :commands (org-roam-node-find org-roam-node-insert org-roam-buffer-toggle)
      :init
      ;; 清残留 sqlite3 子进程：Emacs 被系统杀掉时子进程成孤儿，独占
      ;; org-roam.db 文件锁，新连接打开同一 db 时阻塞直至 emacsql-wait
      ;; 超时（30s）。pkill -f 按 db 完整路径匹配，不影响其它 sqlite3。
      (when (executable-find "pkill")
        (call-process "pkill" nil nil nil "-f"
                      (expand-file-name ".cache/emacs/org-roam.db"
                                        custom:data-home)))
      (setq org-roam-database-connector 'sqlite3)
      :custom
      (org-roam-directory custom:org-roam-directory)
      ;; db 放缓存区，不随 Syncthing 同步（各端独立重建）
      (org-roam-db-location
       (expand-file-name ".cache/emacs/org-roam.db" custom:data-home))
      (org-roam-completion-everywhere nil)
      :config
      ;; 不开 org-roam-db-autosync-mode：其开启时的一次全量
      ;; org-roam-db-sync 在真机 FUSE 共享存储上分钟级阻塞主线程（db
      ;; 被锁时每条查询还要各等满超时），只取其增量部分——保存后更新
      ;; 该文件索引；全量重建手动 M-x org-roam-db-sync（有进度可预期）
      (add-hook 'after-save-hook #'custom/org-roam-update-on-save))))

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

;; ─── appt 议程提醒：Android 走系统通知 ────────────────────────────
;; 常规 App 语义：到点弹系统通知栏（Emacs 前台/后台都触达，点击回
;; Emacs），而非只在 frame 内弹窗。进程被杀则提醒随之消失——端口靠
;; 常驻通知保命，存活率尚可但不保证。

(declare-function android-notifications-notify "androidselect.c")
(declare-function appt-activate "appt")
(declare-function appt-disp-window "appt")
(declare-function org-agenda-to-appt "org-agenda")
(defvar appt-disp-window-function)

(defun custom/appt-notify (min-to-app new-time msg)
  "appt 提醒出口：Android 发系统通知，其余平台回退内置弹窗。
MIN-TO-APP/NEW-TIME/MSG 任一可为 list（多条议程同时到点）。"
  (if (fboundp 'android-notifications-notify)
      (android-notifications-notify
       :title "议程提醒"
       :body (format "%s 分钟后：%s"
                     (if (listp min-to-app)
                         (mapconcat #'identity min-to-app ", ")
                       min-to-app)
                     (if (listp msg) (mapconcat #'identity msg "\n") msg))
       :group "Org Agenda"
       :urgency 'normal)
    (appt-disp-window min-to-app new-time msg)))

(when custom:android-p
  ;; agenda 加载后接管提醒出口并建首次提醒表；org-agenda-to-appt 挂在
  ;; finalize 上，agenda 每次刷新重建（deadline/scheduled/timestamp）
  (with-eval-after-load 'org-agenda
    (require 'appt)
    (setq appt-disp-window-function #'custom/appt-notify)
    (appt-activate 1)
    (add-hook 'org-agenda-finalize-hook #'org-agenda-to-appt)
    (org-agenda-to-appt))
  ;; 不挂绝对计时兜底：org-agenda 加载重（数秒），绝对计时会抢占
  ;; 输入；提醒是尽力而为的增强，让位交互流畅度
  (run-with-idle-timer 90 nil (lambda () (require 'org-agenda))))

(provide 'init-org)
;;; init-org.el ends here
