;;; init-bar.el --- 官方 tool-bar：全局命令按钮（Papirus 图标，Android 底部） -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 全局命令按钮由官方 tool-bar 承载：Android 底部（thumb 区），
;; 按钮触控面积用 margin 放大。
;; 图标 = Papirus symbolic 矢量（data/icons/*.svg，GPL-3.0，`just
;; icons' 重建）：SVG 直渲任意缩放，加载时把 ColorScheme-Text 的 CSS
;; 色替换为当前主题色（深浅色各自 defcustom）；无 librsvg 的构建
;; 回退 72px 中灰 PNG。

;;; Code:

(defcustom custom/bar-icon-height 48
  "tool-bar 图标显示高度（像素）。SVG 矢量任意缩放；PNG 兜底资产为 2× 超采样。"
  :type 'integer
  :group 'emacs-mobile)

(defcustom custom/bar-button-margin 6
  "tool-bar 按钮边距（触控 padding，像素）。"
  :type 'integer
  :group 'emacs-mobile)

(defcustom custom/bar-icon-color-light "#3d3d3d"
  "浅色主题下的图标色（Papirus symbolic 重着色目标）。"
  :type 'string
  :group 'emacs-mobile)

(defcustom custom/bar-icon-color-dark "#c8c8c8"
  "深色主题下的图标色（Papirus symbolic 重着色目标）。"
  :type 'string
  :group 'emacs-mobile)

(defun custom/bar--icon-color ()
  "当前主题对应的图标色（主题未定时按浅色）。"
  (if (and (boundp 'custom/color-scheme-current-mode)
           (eq custom/color-scheme-current-mode 'dark))
      custom/bar-icon-color-dark
    custom/bar-icon-color-light))

(defun custom/bar--svg-image (name height)
  "把 data/icons/NAME.svg 重着色为当前主题色后按 HEIGHT 创建图像；
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
            (concat "ColorScheme-Text { color:" (custom/bar--icon-color))
            (with-temp-buffer
              (insert-file-contents svg)
              (buffer-string)))
           'svg t :height height)))))

(defun custom/bar--image (key)
  "构造 KEY 按钮的图标图像：SVG 重着色直渲优先，PNG 兜底。"
  (or (custom/bar--svg-image (symbol-name key) custom/bar-icon-height)
      (find-image
       `((:type png :file ,(concat (symbol-name key) ".png")
                :height ,custom/bar-icon-height)))))

(declare-function custom/save-buffer-and-recentf "init-ui")

(defun custom/bar--add-button (key label command help)
  "向 `tool-bar-map' 添加使用 data/icons/<KEY> 图标的按钮。"
  (define-key tool-bar-map (vector key)
    `(menu-item ,label ,command
                :help ,help
                :image ,(custom/bar--image key))))

(defvar custom/bar--installed-color nil
  "上次安装按钮时的图标色（色未变的重装直接跳过）。")

(defun custom/bar--install ()
  "安装底部 tool-bar 命令按钮（Android 启动时调用）。"
  ;; 主题加载后 advice 会按新色重装一次；色相同则跳过（省一遍 SVG 读取）
  (let ((color (custom/bar--icon-color)))
    (unless (equal color custom/bar--installed-color)
      (setq custom/bar--installed-color color)
      ;; 底部 tool-bar 须设 frame parameter（bug#64174），三处同设覆盖当前与后续 frame
      (setq tool-bar-position 'bottom)
      (set-frame-parameter nil 'tool-bar-position 'bottom)
      (add-to-list 'default-frame-alist '(tool-bar-position . bottom))

      ;; 按钮过小是 Android 已知缺陷（margins 不随密度缩放），边距作触控 padding 单独调
      (setq tool-bar-button-margin custom/bar-button-margin)

      ;; image-load-path 须在 find-image 调用前就位
      (add-to-list 'image-load-path
                   (expand-file-name "data/icons" user-emacs-directory))

      ;; 按钮表（10 钮单行）：首位 = modifier-bar 显隐开关
      (setq tool-bar-map (make-sparse-keymap))
      (custom/bar--add-button 'modbar "修"
                              #'custom/touch-toggle-modifier-bar
                              "显示/隐藏修饰键栏")
      (custom/bar--add-button 'open "开" #'custom/touch-find-file
                              "打开文件（默认共享存储根）")
      (custom/bar--add-button 'save "存" #'custom/save-buffer-and-recentf
                              "保存并记录最近文件")
      (custom/bar--add-button 'copy "复" #'custom/touch-copy "复制选区/当前行")
      (custom/bar--add-button 'paste "贴" #'yank "粘贴 (C-y)")
      (custom/bar--add-button 'cut "剪" #'custom/touch-cut "剪切选区/当前行")
      (custom/bar--add-button 'search "搜" #'custom/touch-search
                              "搜索（rg 或当前缓冲区）")
      (custom/bar--add-button 'theme "色" #'custom/color-scheme-toggle
                              "切换深浅色主题")
      (custom/bar--add-button 'config "配" #'custom/touch-open-config
                              "打开配置文件夹（dired）")
      (custom/bar--add-button 'dashboard "盘" #'dashboard-open
                              "打开/刷新仪表盘")
      ;; keymap 按插入逆序渲染，反转一次使显示顺序 = 定义顺序（修=最左）
      (setq tool-bar-map (cons 'keymap (reverse (cdr tool-bar-map))))
      (tool-bar-mode 1))))

(when custom:android-p
  (custom/bar--install)
  ;; 主题切换后重装：SVG 图标按主题重着色
  (advice-add 'custom/color-scheme-apply-theme :after
              (lambda (&rest _)
                (when (display-graphic-p)
                  (custom/bar--install)))))

(provide 'init-bar)
;;; init-bar.el ends here
