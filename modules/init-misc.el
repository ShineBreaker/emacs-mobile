;;; init-misc.el --- 终饰：recentf / savehist / saveplace -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 持久化状态统一落 custom:var-directory（~/.local/state/emacs，目录
;; 由 init-basis 定义）。Android 后台被杀时 kill-emacs-hook 不执行：
;; recentf 除显式保存点（失焦/保存按钮，见 init-ui.el）外叠加内置
;; 自动保存定时器（31+）兜底，saveplace 同用定时器。

;;; Code:

(declare-function server-running-p "server")

(use-package recentf
  :config
  ;; 默认值 mode 会在 recentf-mode 开启时立即对全表逐条 file-readable-p；
  ;; 最近文件多在 FUSE 共享存储，启动期百次级系统调用阻塞首屏，改为空闲时清理
  (setq recentf-auto-cleanup 'never)
  (recentf-mode)
  (run-with-idle-timer 5 nil #'recentf-cleanup)
  :custom
  (recentf-save-file (expand-file-name "recentf" custom:var-directory))
  (recentf-max-saved-items 100)
  (recentf-autosave-interval 300))

(use-package savehist
  :init
  (savehist-mode)
  :custom
  (savehist-file (expand-file-name "history" custom:var-directory)))

(use-package saveplace
  :init
  (save-place-mode)
  :custom
  (save-place-file (expand-file-name "places" custom:var-directory))
  (save-place-autosave-interval 300))

;; 从其他 app 打开文件 / org-protocol 链接由 emacsclient 转交本会话，
;; 要求 server 在跑；socket 落在 $TMPDIR/emacs<uid>，emacsclient 同规则查找
(when custom:android-p
  (require 'server)
  (unless (server-running-p) (server-start)))

;; ─── 真机性能诊断 ───────────────────────────────────────────────────
;; 启动路径耗时只能真机测（桌面 I/O 与 CPU 差距大）。本命令现场重测
;; 关键路径：数字明显大于桌面（列目录通常 <0.01s）即说明是存储/CPU
;; 瓶颈，否则是代码路径问题。

(declare-function custom/dashboard--recent-roam-files "init-dashboard")
(declare-function custom/dashboard--note-title "init-dashboard")

(defun custom/perf--elapsed (thunk)
  "执行 THUNK，返回 (耗时 . 结果)。"
  (let ((t0 (float-time)))
    (let ((res (funcall thunk)))
      (cons (- (float-time) t0) res))))

(defun custom/perf-report ()
  "实测关键路径耗时并弹出 buffer（真机排障用）。"
  (interactive)
  (let* ((roam (custom/perf--elapsed
                (lambda ()
                  (length (directory-files custom:org-roam-directory t
                                           "\\.org\\'")))))
         (dash (custom/perf--elapsed
                (lambda () (length (custom/dashboard--recent-roam-files 4)))))
         (title (custom/perf--elapsed
                 (lambda ()
                   (let ((f (car (custom/dashboard--recent-roam-files 1))))
                     (and f (custom/dashboard--note-title f))))))
         (buf (get-buffer-create "*emacs-mobile 性能*")))
    (with-current-buffer buf
      (fundamental-mode)
      (erase-buffer)
      (insert
       (format "启动总耗时:        %s
已加载特性数:      %d
GC 阈值:           %s
recentf 条目数:    %d
org 笔记目录:      %s

── 现场重测（缓存可能已热，看量级不看绝对值）──
列笔记目录:        %.3f s（%d 个 .org）
仪表盘首屏数据:    %.3f s（%d 条）
笔记标题读取:      %.3f s（首条 %s）

参考：桌面列目录 <0.01s。真机上明显更大属 FUSE 存储差异；
若数字正常但交互卡顿，瓶颈在代码路径而非 I/O。"
               (emacs-init-time)
               (length features)
               gc-cons-threshold
               (and (bound-and-true-p recentf-mode) (length recentf-list))
               (or custom:org-roam-directory "(未定义)")
               (car roam) (cdr roam)
               (car dash) (cdr dash)
               (car title) (or (cdr title) "(无)")))
      (goto-char (point-min)))
    (pop-to-buffer buf)))

(provide 'init-misc)
;;; init-misc.el ends here
