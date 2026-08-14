;;; early-init.el --- emacs-mobile 启动期优化 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 真机部署模型：完整配置仓库 clone 在 Termux home（git 可用），Emacs
;; 自身的 ~/.emacs.d 只复制本文件与 init.el 两个副本。
;;
;; Android 上本文件探测到 Termux 仓库时：重定向 `user-emacs-directory'
;; 并加载仓库版 early-init（注意：init.el 的加载位置不随重定向变化，
;; 由 init.el 自行转发，见该文件）。仓库内运行（桌面沙箱）或无 Termux
;; 时直接执行下方本体。
;;
;; 本体优化项（从桌面移植，exec-path 从 Guix 改为 Termux bin）：
;; 1. 禁用 package.el（用 straight 管理包）
;; 2. 提高 GC 阈值（启动后由 init-basis 复位）

;;; Code:

(setq load-prefer-newer nil)

(defconst custom:termux-repo
  "/data/data/com.termux/files/home/emacs-mobile/"
  "Termux home 下的完整配置仓库路径（真机部署模型）。")

(if (and (eq system-type 'android)
         (file-directory-p (expand-file-name "modules" custom:termux-repo))
         (not (file-equal-p user-emacs-directory custom:termux-repo)))
    ;; Emacs home 副本：重定向后加载仓库版本（其内 user-emacs-directory
    ;; 已等于仓库，file-equal-p 成立，不再转发，执行本体）
    (progn
      (setq user-emacs-directory custom:termux-repo)
      (load (expand-file-name "early-init.el" custom:termux-repo) nil t))

  ;; ── 本体（仓库内运行 / 桌面沙箱） ──────────────────────────────

  ;; 禁用 package.el 自动初始化（使用 straight 管理包）
  (setq package-enable-at-startup nil)

  ;; exec-path 前置（必须在 modules 解析外部命令之前）。
  ;; Android 上注入 Termux bin 以获得 git/rg 等命令；无 Termux 则跳过。
  (when (eq system-type 'android)
    (let ((termux-bin "/data/data/com.termux/files/usr/bin"))
      (when (file-directory-p termux-bin)
        (setenv "PATH" (concat termux-bin path-separator (getenv "PATH")))
        (add-to-list 'exec-path termux-bin))))

  ;; 启动性能优化（启动后由 init-basis 复位）
  (setq gc-cons-threshold most-positive-fixnum
        gc-cons-percentage 0.6))

;;; early-init.el ends here
