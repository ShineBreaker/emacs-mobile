;;; init-bar.el --- 官方 tool-bar：全局命令按钮（PNG 图标，Android 底部） -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 方案 F（2026-08-15 拍板）：全局命令按钮回归官方 tool-bar。
;; · 前身方案 E（side window 字符 bar）废弃根因：bar 是普通 buffer，
;;   tap 按钮会把 bar 的 window 选中，复制/剪切/撤销/切缓冲区等命令
;;   全部落到 *mobile-bar* 自身（真机踩坑）；官方 tool-bar 是 frame
;;   部件，tap 不改选中窗口，机制上根治。
;; · 图标 = Maple NF 字形渲染的 56px PNG（data/icons/，中灰双主题
;;   通吃，`just icons` 幂等重建）；`tool-bar-add-item' 只认 etc/images
;;   内置图标，自定义 PNG 须手写 menu-item :image。
;; · Android 底部（thumb 区）；按钮触控面积用 margin 放大。

;;; Code:

(defcustom custom/bar-icon-height 36
  "tool-bar 图标显示高度（像素）。资产为 2× 超采样 PNG（72px），
spec :height 整数倍下采样保清晰；常规调整显示尺寸不须重新生成
资产。真机按体感调整。"
  :type 'integer
  :group 'emacs-mobile)

(defcustom custom/bar-button-margin 6
  "tool-bar 按钮边距（触控 padding，像素）。0 视觉最紧凑。"
  :type 'integer
  :group 'emacs-mobile)

(defun custom/bar--add-button (key label command help)
  "向 `tool-bar-map' 添加使用 data/icons/<KEY>.png 图标的按钮。"
  (define-key tool-bar-map (vector key)
    `(menu-item ,label ,command
                :help ,help
                :image ,(find-image
                         `((:type png :file ,(concat (symbol-name key)
                                                     ".png")
                                  :height ,custom/bar-icon-height))))))

(defun custom/bar--install ()
  "安装底部 tool-bar 命令按钮（Android 启动时调用，桌面可手动调用验证）。"
  ;; 底部 tool-bar：Emacs 30.2 Android 的正确入口是 frame parameter
  ;; （bug#64174），全局 setq 无效；三处同设覆盖当前与后续 frame。
  (setq tool-bar-position 'bottom)
  (set-frame-parameter nil 'tool-bar-position 'bottom)
  (add-to-list 'default-frame-alist '(tool-bar-position . bottom))

  ;; 按钮过小是 Android 版已知缺陷（margins 不随屏幕密度缩放），
  ;; 边距作为触控 padding，与图标高度（custom/bar-icon-height）分别调
  (setq tool-bar-button-margin custom/bar-button-margin)

  ;; image-load-path 须在 find-image 调用前就位（一期教训）
  (add-to-list 'image-load-path
               (expand-file-name "data/icons" user-emacs-directory))

  ;; 按钮表（首尾皆工具栏语义入口）：首位 = modifier-bar 显隐开关
  (setq tool-bar-map (make-sparse-keymap))
  (custom/bar--add-button 'modbar "修"
                          #'custom/touch-toggle-modifier-bar
                          "显示/隐藏修饰键栏")
  (custom/bar--add-button 'save "存" #'save-buffer "保存 (C-x C-s)")
  (custom/bar--add-button 'copy "复" #'custom/touch-copy "复制选区/当前行")
  (custom/bar--add-button 'cut "剪" #'custom/touch-cut "剪切选区/当前行")
  (custom/bar--add-button 'paste "贴" #'yank "粘贴 (C-y)")
  (custom/bar--add-button 'undo "撤" #'undo "撤销")
  (custom/bar--add-button 'redo "重" #'undo-redo "重做")
  (custom/bar--add-button 'search "搜" #'custom/touch-search
                          "搜索（rg 或当前缓冲区）")
  (custom/bar--add-button 'recenter "中" #'recenter-top-bottom "当前行回中")
  (custom/bar--add-button 'theme "色" #'custom/color-scheme-toggle
                          "切换深浅色主题")
  (custom/bar--add-button 'config "配" #'custom/touch-open-config
                          "打开配置 init.el")
  (custom/bar--add-button 'dashboard "盘" #'dashboard-open
                          "打开/刷新仪表盘")
  (tool-bar-mode 1))

(when custom:android-p
  (custom/bar--install))

(provide 'init-bar)
;;; init-bar.el ends here
