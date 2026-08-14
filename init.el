;;; init.el --- emacs-mobile 入口，按序加载各模块 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 固定入口，仅将 modules/ 加入 load-path 并按序 require。
;; 模块顺序即依赖顺序：basis → packages → 其余。
;;
;; 真机部署：本文件与 early-init.el 复制到 Emacs 的 ~/.emacs.d，完整
;; 仓库在 Termux home。early-init 已重定向 `user-emacs-directory'，
;; 下方 load-path/require 随之指向仓库 modules；若 early-init 未运行
;; （副本缺失等），此处自行重定向并转发到仓库 init.el。

;;; Code:

(defvar custom:termux-repo)  ; early-init.el

(if (and (eq system-type 'android)
         (file-directory-p (expand-file-name "modules" custom:termux-repo))
         (not (file-equal-p user-emacs-directory custom:termux-repo)))
    ;; user-emacs-directory 未经 early-init 重定向：手动转发
    (progn
      (setq user-emacs-directory custom:termux-repo)
      (load (expand-file-name "init.el" custom:termux-repo) nil t))

  (add-to-list 'load-path (expand-file-name "modules" user-emacs-directory))

  (require 'init-basis)
  (require 'init-packages)
  (require 'init-android)
  (require 'init-ui)
  (require 'init-touch)
  (require 'init-completion)
  (require 'init-org)
  (require 'init-reading)
  (require 'init-misc))

;;; init.el ends here
