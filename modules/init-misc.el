;;; init-misc.el --- 终饰：recentf / savehist / saveplace -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 持久化状态统一落 var/（不入 git）。savehist 让 vertico 补全历史跨会话。

;;; Code:

(defconst custom:var-directory
  (expand-file-name "var/" user-emacs-directory)
  "本地状态文件目录。")
(unless (file-exists-p custom:var-directory)
  (make-directory custom:var-directory t))

(use-package recentf
  :init
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

(provide 'init-misc)
;;; init-misc.el ends here
