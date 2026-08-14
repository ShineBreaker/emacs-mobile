;;; init.el --- emacs-mobile 入口，按序加载各模块 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 固定入口，仅将 modules/ 加入 load-path 并按序 require。
;; 模块顺序即依赖顺序：basis → packages → 其余。

;;; Code:

(add-to-list 'load-path (expand-file-name "modules" user-emacs-directory))

(require 'init-basis)
(require 'init-packages)
(require 'init-android)
(require 'init-ui)
(require 'init-touch)
(require 'init-completion)
(require 'init-org)
(require 'init-reading)
(require 'init-misc)

;;; init.el ends here
