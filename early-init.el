;;; early-init.el --- emacs-mobile 启动期优化 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 在 GUI 初始化之前尽早执行：加速启动、避免 package.el 介入。
;; 从桌面配置移植，exec-path 前置从 Guix profile 改为 Termux bin。

;;; Code:

(setq load-prefer-newer nil)

;; 禁用 package.el 自动初始化（使用 straight 管理包）
(setq package-enable-at-startup nil)

;; exec-path 前置（必须在 modules 解析外部命令之前）。
;; Android 上注入 Termux bin 以获得 git/rg 等命令；桌面无此目录，自动跳过。
(when (eq system-type 'android)
  (let ((termux-bin "/data/data/com.termux/files/usr/bin"))
    (when (file-directory-p termux-bin)
      (setenv "PATH" (concat termux-bin path-separator (getenv "PATH")))
      (add-to-list 'exec-path termux-bin))))

;; 启动性能优化（启动后由 init-basis 复位）
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;;; early-init.el ends here
