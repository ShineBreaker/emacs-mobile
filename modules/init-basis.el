;;; init-basis.el --- 基础常量、平台检测与启动优化复位 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 全局常量（custom: 命名空间）与平台检测，被后续模块依赖。

;;; Code:

(defgroup emacs-mobile nil
  "emacs-mobile 配置。"
  :group 'emacs)

(defconst custom:android-p (eq system-type 'android)
  "是否运行在 Android 原生 Emacs 上。")

;; 数据区根目录（缓存/状态）：Android 用 Termux home，桌面用 HOME（沙箱隔离）
(defconst custom:data-home
  (if (eq system-type 'android)
      "/data/data/com.termux/files/home/"
    (expand-file-name "~/"))
  "缓存与持久化状态的根目录。")

;; 持久化状态目录（recentf/savehist/saveplace/主题深浅色状态）
(defconst custom:var-directory
  (expand-file-name ".local/state/emacs/" custom:data-home)
  "持久化状态目录。")
(unless (file-directory-p custom:var-directory)
  (make-directory custom:var-directory t))

;; org 笔记根目录：Android 真机路径（Syncthing 同步）存在则用之，
;; 否则回退本地目录（桌面沙箱可全功能测试）
(defconst custom:org-directory
  (if (file-directory-p "/storage/emulated/0/Data/Syncthing/notebook/org/")
      "/storage/emulated/0/Data/Syncthing/notebook/org/"
    (expand-file-name "org/" user-emacs-directory))
  "org 笔记根目录。")
(defconst custom:org-roam-directory
  (expand-file-name "roam" custom:org-directory)
  "org-roam 笔记目录。")
(defconst custom:org-inbox-file
  (expand-file-name "inbox.org" custom:org-directory)
  "capture inbox 文件。")

;; 启动优化复位（early-init 推高了 GC 阈值并绕过文件名处理器）。
;; 复位放 startup 末尾：after-init 的 dashboard 生成仍在高阈值下进行。
(defun custom/restore-startup-perf ()
  "恢复 GC 阈值与文件名处理器，空闲时清一次启动垃圾。"
  (setq gc-cons-threshold (* 16 1024 1024)   ; 16MB 稳态
        gc-cons-percentage 0.1)
  (when (boundp 'custom--startup-file-name-handlers)
    (setq file-name-handler-alist custom--startup-file-name-handlers))
  (run-with-idle-timer 3 nil #'garbage-collect))
(add-hook 'emacs-startup-hook #'custom/restore-startup-perf)

;; ─── modules 后台预编译 ─────────────────────────────────────────────
;; 源码慢于字节码（Android 慢 CPU 差距放大）；空闲逐文件补齐，用户输入
;; 会重置空闲计时自然避让。

(defun custom/compile-modules ()
  "编译 modules/ 下缺失或过期的 .el，编译后再安排下一轮。"
  (let* ((dir (expand-file-name "modules" user-emacs-directory))
         (els (seq-filter
               (lambda (el)
                 (let ((elc (concat el "c")))
                   (or (not (file-exists-p elc))
                       (time-less-p
                        (file-attribute-modification-time
                         (file-attributes elc))
                        (file-attribute-modification-time
                         (file-attributes el))))))
               (directory-files dir t "\\.el\\'"))))
    (when els
      (byte-compile-file (car els))
      (run-with-idle-timer 0.2 nil #'custom/compile-modules))))

(add-hook 'emacs-startup-hook
          (lambda ()
            (when (file-writable-p (expand-file-name "modules"
                                                     user-emacs-directory))
              (run-with-idle-timer 8 nil #'custom/compile-modules))))

(provide 'init-basis)
;;; init-basis.el ends here
