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

;; 数据区根目录（缓存/状态）：Android 用 Termux home，桌面用 HOME（沙箱隔离）
(defconst custom:data-home
  (if (eq system-type 'android)
      "/data/data/com.termux/files/home/"
    (expand-file-name "~/"))
  "缓存与持久化状态的根目录。")

;; 持久化状态目录（recentf/savehist/saveplace/主题深浅色状态）
(defconst custom:var-directory
  (expand-file-name ".local/state/emacs/" custom:data-home)
  "持久化状态目录。")
(unless (file-directory-p custom:var-directory)
  (make-directory custom:var-directory t))

;; org 笔记根目录：Android 真机路径（Syncthing 同步）存在则用之，
;; 否则回退本地目录（桌面沙箱可全功能测试）
(defconst custom:org-directory
  (if (file-directory-p "/storage/emulated/0/Data/Syncthing/notebook/org/")
      "/storage/emulated/0/Data/Syncthing/notebook/org/"
    (expand-file-name "org/" user-emacs-directory))
  "org 笔记根目录。")
(defconst custom:org-roam-directory
  (expand-file-name "roam" custom:org-directory)
  "org-roam 笔记目录。")
(defconst custom:org-inbox-file
  (expand-file-name "inbox.org" custom:org-directory)
  "capture inbox 文件。")

;; ─── 图标与字形（唯一入口：tool-bar 按钮、modifier-bar 徽章、mode-line 字形） ──

(defun custom/icon--svg-image (name color height)
  "重着色 data/icons/NAME.svg 的 ColorScheme-Text 为 COLOR 后按 HEIGHT 建图；
无 librsvg 或文件缺失时返回 nil。"
  (let ((svg (expand-file-name (concat name ".svg")
                               (expand-file-name "data/icons"
                                                 user-emacs-directory))))
    (and (image-type-available-p 'svg)
         (file-exists-p svg)
         (ignore-errors
          (create-image
           (replace-regexp-in-string
            "ColorScheme-Text { color:#[0-9a-fA-F]\\{6\\}"
            (concat "ColorScheme-Text { color:" color)
            (with-temp-buffer
              (insert-file-contents svg)
              (buffer-string)))
           'svg t :height height)))))

(defun custom/icon-asset (key &optional mod height color)
  "KEY 按钮图标：MOD 非 nil 时查 mod-KEY 徽章（PBM 优先 PNG 兜底），
否则查 KEY 的 SVG（按 COLOR 重着色）/PNG。按序回退，全部缺失返回 nil。"
  (let ((dir (expand-file-name "data/icons" user-emacs-directory)))
    (if mod
        (find-image
         `((:type pbm :file ,(expand-file-name (format "mod-%s.pbm" key) dir))
           (:type png :file ,(expand-file-name (format "mod-%s.png" key) dir))))
      (or (custom/icon--svg-image key color height)
          (find-image
           `((:type png :file ,(expand-file-name (format "%s.png" key) dir)
                    :height ,height)))))))

(defvar custom/glyph-nf-tty
  (equal (getenv "EMACS_MOBILE_NF_TTY") "1")
  "tty 下宿主终端是否带 Nerd Font 字形（tmux 校验对齐真机宽度模型用，
经环境变量 EMACS_MOBILE_NF_TTY=1 开启）。")

(defun custom/glyph-nf-p ()
  "当前环境是否按 NF 字形渲染（GUI 恒是；tty 由 `custom/glyph-nf-tty' 开）。"
  (or (display-graphic-p) custom/glyph-nf-tty))

(defun custom/glyph (code fallback)
  "有 NF 字形的环境返回 CODE，其余 tty 返回 FALLBACK 文字。
字形降级的唯一入口。"
  (if (custom/glyph-nf-p)
      code
    fallback))

;; NF 私用区字形宽度：GUI 按 Maple advance 渲染恰 1 列，宽度表默认记
;; 1 即与渲染一致（置 2 会布局 2 列、字形墨迹占左半，高亮框/间距错位）；
;; 终端把 PUA 记 2 列（tmux/utf8proc），NF 校验模式下同步置 2 保对齐。
(when custom/glyph-nf-tty
  (set-char-table-range char-width-table '(#xE000 . #xF8FF) 2))

;; 启动优化复位（early-init 推高了 GC 阈值并绕过文件名处理器）。
;; 复位放 startup 末尾：after-init 的 dashboard 生成仍在高阈值下进行。
(defun custom/restore-startup-perf ()
  "恢复 GC 阈值与文件名处理器，空闲时清一次启动垃圾。"
  (setq gc-cons-threshold (* 16 1024 1024)   ; 16MB 稳态
        gc-cons-percentage 0.1)
  (when (boundp 'custom--startup-file-name-handlers)
    (setq file-name-handler-alist custom--startup-file-name-handlers))
  (run-with-idle-timer 3 nil #'garbage-collect))
(add-hook 'emacs-startup-hook #'custom/restore-startup-perf)

;; ─── modules 后台预编译 ─────────────────────────────────────────────
;; 源码慢于字节码（Android 慢 CPU 差距放大）；空闲逐文件补齐，用户输入
;; 会重置空闲计时自然避让。

(defun custom/compile-modules ()
  "编译 modules/ 下缺失或过期的 .el，编译后再安排下一轮。"
  (let* ((dir (expand-file-name "modules" user-emacs-directory))
         (els (seq-filter
               (lambda (el)
                 (let ((elc (concat el "c")))
                   (or (not (file-exists-p elc))
                       (time-less-p
                        (file-attribute-modification-time
                         (file-attributes elc))
                        (file-attribute-modification-time
                         (file-attributes el))))))
               (directory-files dir t "\\.el\\'"))))
    (when els
      (byte-compile-file (car els))
      (run-with-idle-timer 0.2 nil #'custom/compile-modules))))

(add-hook 'emacs-startup-hook
          (lambda ()
            (when (file-writable-p (expand-file-name "modules"
                                                     user-emacs-directory))
              (run-with-idle-timer 8 nil #'custom/compile-modules))))

(provide 'init-basis)
;;; init-basis.el ends here
