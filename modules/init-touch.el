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

(defun custom/touch--add-button (key label command help)
  "向 `tool-bar-map' 添加使用 data/icons/<KEY>.png 图标的按钮。"
  (define-key tool-bar-map (vector key)
    `(menu-item ,label ,command
                :help ,help
                :image ,(find-image
                         `((:type png :file ,(concat (symbol-name key)
                                                     ".png")))))))

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

  ;; tool-bar 命令组（flat，顺序即分组：文件│Org│导航│视图）。
  ;; 图标：Maple Mono NF CN 的 Nerd 字形渲染的 96px PNG（data/icons/，
  ;; `just icons` 可重建）。直接重置全局 `tool-bar-map' 后逐个添加
  ;; ——`tool-bar-add-item' 只认 etc/images 内置图标，自定义 PNG 需手写
  ;; menu-item 的 :image。
  (add-to-list 'image-load-path
               (expand-file-name "data/icons" user-emacs-directory))
  (setq tool-bar-map (make-sparse-keymap))
  (custom/touch--add-button 'save "存" #'save-buffer "保存 (C-x C-s)")
  (custom/touch--add-button 'undo "撤" #'undo "撤销")
  (custom/touch--add-button 'redo "重" #'undo-redo "重做")
  ;; Org 组：命令由 init-org.el 提供，点击时才解析符号
  (custom/touch--add-button 'capture "抓" #'org-capture "快速捕获")
  (custom/touch--add-button 'agenda "程" #'org-agenda "议程")
  (custom/touch--add-button 'roam "笔" #'org-roam-node-find "查找/新建 Roam 笔记")
  ;; 导航组
  (custom/touch--add-button 'buffer "换" #'consult-buffer "切换缓冲区")
  (custom/touch--add-button 'search "搜" #'custom/touch-search "搜索（rg 或当前缓冲区）")
  ;; 视图组
  (custom/touch--add-button 'recenter "中" #'recenter-top-bottom "当前行回中"))

;; 桌面：无需工具栏与修饰键栏
(unless custom:android-p
  (tool-bar-mode -1))

(provide 'init-touch)
;;; init-touch.el ends here
