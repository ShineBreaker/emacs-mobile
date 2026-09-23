;;; init-reading.el --- 阅读栈：eww / info / nov（epub） -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; eww/info 内置即用；nov.el 处理 epub。PDF 不支持（pdf-tools 需 C
;; 编译，Android 不可行）。触屏入口走 mode-line 钮（dired 先例）。

;;; Code:

;; 链接默认在 eww 内打开（外部浏览器走 mode-line「外」钮，见下）
(with-eval-after-load 'browse-url
  (setq browse-url-browser-function 'eww-browse-url))

;; ─── eww 触屏钮：回退 + 交外部浏览器 ──────────────────────────────
;; 内嵌阅读为主，复杂页面一键交给系统浏览器（Android Intent）。

(declare-function custom/mode-line--button "init-ui")
(declare-function custom/mode-line--add-local-buttons "init-ui")
(declare-function android-browse-url "android-win")
(declare-function browse-url-default-browser "browse-url")
(declare-function eww-back-url "eww")
(defvar eww-current-url)

(defun custom/browse-url-external (url)
  "把 URL 交给系统外部浏览器（Android 走 Intent，桌面走默认浏览器）。"
  (interactive "MURL: ")
  (if (fboundp 'android-browse-url)
      (android-browse-url url)
    (browse-url-default-browser url)))

(defun custom/eww-open-external ()
  "eww 当前页交系统外部浏览器打开。"
  (interactive)
  (if (and (boundp 'eww-current-url) eww-current-url)
      (custom/browse-url-external eww-current-url)
    (message "当前无 eww 页面 URL")))

(defconst custom/eww--buttons
  '(("\uF060" "退" "回退上一页 (eww-back)" eww-back-url)
    ("\uF08E" "外" "外部浏览器打开当前页" custom/eww-open-external))
  "eww mode-line 钮表：(NF 字形 tty 回退 帮助 命令)。")

(defun custom/eww--mode-line-buttons ()
  "eww mode-line 钮串。"
  (mapconcat #'custom/mode-line--button custom/eww--buttons nil))

(defun custom/eww--setup-mode-line ()
  "eww buffer：右端钮组前插入回退/外开钮。"
  (custom/mode-line--add-local-buttons #'custom/eww--mode-line-buttons))

(add-hook 'eww-mode-hook #'custom/eww--setup-mode-line)

(defvar shr-sliced-image-height)  ; 内置 shr.el

;; 高图按窗高比例切片（0.7 = 超七成即切）：滚动逐片走过不跳整图，
;; eww/nov 共用 shr 渲染
(with-eval-after-load 'shr
  (setq shr-sliced-image-height 0.7))

(use-package nov
  :mode ("\\.epub\\'" . nov-mode))

(provide 'init-reading)
;;; init-reading.el ends here
