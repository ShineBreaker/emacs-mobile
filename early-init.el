;;; early-init.el --- emacs-mobile 启动期优化 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 真机部署：完整配置仓库 clone 在 Termux home（git 可用），Emacs 自身
;; 的 ~/.emacs.d 只复制本文件与 init.el 两个副本。
;;
;; Android 上探测到 Termux 仓库时：重定向 `user-emacs-directory' 并加载
;; 仓库版 early-init（init.el 的加载位置不随重定向变化，由 init.el
;; 自行转发，见该文件）。仓库内运行（桌面沙箱）或无 Termux 时直接
;; 执行下方本体。
;;
;; 本体优化项：禁用 package.el（用 straight 管理包）、提高 GC 阈值
;; （启动后由 init-basis 复位）、绕过文件名处理器（同前）、frame 参数
;; 抑制 menu/tool/scroll bar（先建后拆的浪费，Android 的 tool-bar 由
;; init-bar 显式再开）、exec-path 前置 Termux bin。

;;; Code:

;; modules/ 有后台补编译的 .elc：源码更新时必须优先加载新源码
;; （否则 git pull 后的首次启动仍跑旧 .elc）
(setq load-prefer-newer t)

(defconst custom:termux-repo
  "/data/data/com.termux/files/home/.config/emacs/"
  "Termux home 下的完整配置仓库路径。")

(if (and (eq system-type 'android)
         (file-directory-p (expand-file-name "modules" custom:termux-repo))
         (not (file-equal-p user-emacs-directory custom:termux-repo)))
    ;; Emacs home 副本：重定向后加载仓库版本（其内 user-emacs-directory
    ;; 已等于仓库，file-equal-p 成立，不再转发，直接执行本体）
    (progn
      (setq user-emacs-directory custom:termux-repo)
      (load (expand-file-name "early-init.el" custom:termux-repo) nil t))

  ;; ── 本体（仓库内运行 / 桌面沙箱） ──────────────────────────────

  ;; 禁用 package.el 自动初始化（使用 straight 管理包）；跳过 site-start/
  ;; default.el（真机无，桌面沙箱有 guix site-lisp）
  (setq package-enable-at-startup nil
        inhibit-default-init t
        site-run-file nil)

  ;; frame 参数抑制：初始 frame 不建 menu/tool/scroll bar（Android 的
  ;; tool-bar 由 init-bar 显式开启，避免先建默认栏再拆）
  (dolist (param '((menu-bar-lines . 0) (tool-bar-lines . 0)
                   (vertical-scroll-bars . nil)
                   (horizontal-scroll-bars . nil)))
    (add-to-list 'default-frame-alist param))

  ;; exec-path 前置：Android 注入 Termux bin 以获得 git/rg 等命令
  (when (eq system-type 'android)
    (let ((termux-bin "/data/data/com.termux/files/usr/bin"))
      (when (file-directory-p termux-bin)
        (setenv "PATH" (concat termux-bin path-separator (getenv "PATH")))
        (add-to-list 'exec-path termux-bin))))

  ;; 启动性能优化（启动后由 init-basis 复位）
  (defvar custom--startup-file-name-handlers file-name-handler-alist
    "启动前原 file-name-handler-alist（init-basis 复位用）。")
  (setq gc-cons-threshold most-positive-fixnum
        gc-cons-percentage 0.6
        file-name-handler-alist nil))

;;; early-init.el ends here
