;;; init-touch.el --- 触屏交互：底部单栏切换 + tool-bar 命令组 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 方案 D：底部单栏，mode-line 右端 [⇄] 在 tool-bar（命令态）与
;; modifier-bar（输入态）间互斥切换。切换命令跨平台（mode-line 开关
;; 依赖它）；tool-bar 命令组与 touch-screen-* 选项 Android 守卫。

;;; Code:

;; ─── 修饰键栏切换（跨平台） ─────────────────────────────────────────
;; modifier-bar 的官方语义是「叠加在常规 tool-bar 旁的小工具栏」
;; （documentation: "in addition to the regular tool bar"），
;; 不能与 tool-bar 互斥切换——tool-bar 常显，此处只开关 modifier-bar 叠加。
(defun custom/touch-toggle-modifier-bar ()
  "开关 modifier-bar（修饰键栏，叠加于 tool-bar 旁）。"
  (interactive)
  (if (bound-and-true-p modifier-bar-mode)
      (modifier-bar-mode -1)
    (modifier-bar-mode 1)))

;; 搜索入口：rg 可用走 consult-ripgrep，缺失降级 consult-line
(declare-function consult-ripgrep "consult")
(declare-function consult-line "consult")
(defun custom/touch-search ()
  "搜索。rg 可用时全文检索，否则检索当前缓冲区。"
  (interactive)
  (if (executable-find "rg")
      (call-interactively #'consult-ripgrep)
    (call-interactively #'consult-line)))

;; ─── Android 触屏特化 ───────────────────────────────────────────────

(when custom:android-p
  ;; 底部 tool-bar（拇指可达）。Emacs 30.2 Android 的正确入口是
  ;; frame parameter（bug#64174），全局变量 setq 无效；三处同设覆盖
  ;; 当前 frame 与后续新建 frame，兼容 31+ 的 defcustom 形式。
  (setq tool-bar-position 'bottom)
  (set-frame-parameter nil 'tool-bar-position 'bottom)
  (add-to-list 'default-frame-alist '(tool-bar-position . bottom))

  ;; 按钮过小是 Android 版已知缺陷（margins 不随屏幕密度缩放），
  ;; 用边距放大触控面积；真机实测后在此调整数值。
  (setq tool-bar-button-margin 8)

  ;; 触屏选项：tap 任意处可唤出系统虚拟键盘
  (setq touch-screen-display-keyboard t
        touch-screen-preview-select t
        touch-screen-word-select t
        touch-screen-extend-selection t)

  ;; 触屏无菜单交互场景，关闭菜单栏省一行（命令走 tool-bar / M-x）
  (menu-bar-mode -1)

  ;; 初始态：命令态（tool-bar 开、modifier-bar 关）
  (tool-bar-mode 1)
  (modifier-bar-mode -1)

  ;; tool-bar 命令组（flat，顺序即分组：文件│Org│导航）。
  ;; 官方标准写法：直接重置全局 `tool-bar-map' 后逐个 add——
  ;; `tool-bar-add-item' 操作的就是这个全局 map，不能自造局部 map。
  ;; 图标只采用 Emacs 内置集合（etc/images）中存在的；
  ;; zoom-in/zoom-out/refresh/redo 无图标（会渲染空白），故不做按钮：
  ;; 字号缩放用系统双指手势（Android Emacs 原生调 text-scale）。
  (setq tool-bar-map (make-sparse-keymap))
  (tool-bar-add-item "save" 'save-buffer 'save-buffer :label "存")
  (tool-bar-add-item "undo" 'undo 'undo :label "撤")
  ;; Org 组：命令由 init-org.el 提供，点击时才解析符号
  (tool-bar-add-item "new" 'org-capture 'org-capture :label "抓")
  (tool-bar-add-item "open" 'org-agenda 'org-agenda :label "程")
  (tool-bar-add-item "jump-to" 'org-roam-node-find 'org-roam-node-find
                     :label "笔")
  ;; 导航组
  (tool-bar-add-item "index" 'consult-buffer 'consult-buffer :label "换")
  (tool-bar-add-item "search" 'custom/touch-search 'custom/touch-search
                     :label "搜"))

;; 桌面：无需工具栏与修饰键栏
(unless custom:android-p
  (tool-bar-mode -1))

(provide 'init-touch)
;;; init-touch.el ends here
