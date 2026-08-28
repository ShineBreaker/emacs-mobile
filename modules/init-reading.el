;;; init-reading.el --- 阅读栈：eww / info / nov（epub） -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; eww/info 内置即用；nov.el 处理 epub。PDF 不支持（pdf-tools 需 C
;; 编译，Android 不可行）。

;;; Code:

;; 链接默认在 eww 内打开
(with-eval-after-load 'browse-url
  (setq browse-url-browser-function 'eww-browse-url))

(defvar shr-sliced-image-height)  ; 内置 shr.el

;; 高图按窗高比例切片（0.7 = 超七成即切）：滚动逐片走过不跳整图，
;; eww/nov 共用 shr 渲染
(with-eval-after-load 'shr
  (setq shr-sliced-image-height 0.7))

(use-package nov
  :mode ("\\.epub\\'" . nov-mode))

(provide 'init-reading)
;;; init-reading.el ends here
