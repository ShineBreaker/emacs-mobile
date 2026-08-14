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

;; org 笔记根目录（Syncthing 同步；拼写待真机确认，见 PLAN §15）
(defconst custom:org-directory
  "/storage/emulated/0/Data/Synching/notebook/org/"
  "org 笔记根目录。")
(defconst custom:org-roam-directory
  (expand-file-name "roam" custom:org-directory)
  "org-roam 笔记目录。")

;; 启动优化复位（early-init 期推高了 GC 阈值）
(setq gc-cons-threshold (* 16 1024 1024)   ; 16MB 稳态
      gc-cons-percentage 0.1)

(provide 'init-basis)
;;; init-basis.el ends here
