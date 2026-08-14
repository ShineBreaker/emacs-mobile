;;; init-reading.el --- 阅读栈：eww / info / nov（epub） -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; eww/info 内置即用；nov.el 处理 epub。PDF 首版不支持（pdf-tools 需 C
;; 编译，Android 不可行，见 PLAN §12）。

;;; Code:

;; 手机上链接默认在 eww 内打开（浏览器外链体验差）
(with-eval-after-load 'browse-url
  (setq browse-url-browser-function 'eww-browse-url))

(use-package nov
  :mode ("\\.epub\\'" . nov-mode))

(provide 'init-reading)
;;; init-reading.el ends here
