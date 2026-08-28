;;; init-misc.el --- 终饰：recentf / savehist / saveplace -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 持久化状态统一落 custom:var-directory（~/.local/state/emacs，目录
;; 由 init-basis 定义）。recentf 落盘走显式保存点（失焦保存与 tool-bar
;; 保存按钮，见 init-ui.el）：Android 后台被杀时 kill-emacs-hook 不
;; 执行，定时器在 30.2 亦不存在。

;;; Code:

(declare-function server-running-p "server")

(use-package recentf
  :config
  (recentf-mode)
  :custom
  (recentf-save-file (expand-file-name "recentf" custom:var-directory))
  (recentf-max-saved-items 100))

(use-package savehist
  :init
  (savehist-mode)
  :custom
  (savehist-file (expand-file-name "history" custom:var-directory)))

(use-package saveplace
  :init
  (save-place-mode)
  :custom
  (save-place-file (expand-file-name "places" custom:var-directory)))

;; 从其他 app 打开文件 / org-protocol 链接由 emacsclient 转交本会话，
;; 要求 server 在跑；socket 落在 $TMPDIR/emacs<uid>，emacsclient 同规则查找
(when custom:android-p
  (require 'server)
  (unless (server-running-p) (server-start)))

(provide 'init-misc)
;;; init-misc.el ends here
