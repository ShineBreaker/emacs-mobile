;;; init-touch.el --- 触屏层：官方 modifier-bar + 触屏编辑命令 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 交互组件全部用官方宿主：
;; · 修饰键 → 官方 modifier-bar（tap 后下一个输入带修饰）
;; · 全局命令按钮 → 官方 tool-bar（init-bar.el 安装，底部）
;; · buffer/窗口控制 → mode-line（init-ui.el）

;;; Code:

(declare-function dashboard-open "dashboard")
(declare-function dired-mouse-find-file "dired")
(defvar dired-mode-map)

;; ─── 复制 / 剪切：有选区作用于选区，无选区作用于当前行 ─────────────
;; 无选区时整行操作更符合触屏直觉。

(defun custom/touch-copy ()
  "复制：有选区复制选区，否则复制当前行。"
  (interactive)
  (let* ((regionp (use-region-p))
         (beg (if regionp (region-beginning) (line-beginning-position)))
         (end (if regionp (region-end) (line-end-position))))
    (copy-region-as-kill beg end)
    (message "已复制%s" (if regionp "选区" "当前行"))))

(defun custom/touch-cut ()
  "剪切：有选区剪切选区，否则剪切当前行（连换行整行消失）。"
  (interactive)
  (let* ((regionp (use-region-p))
         (beg (if regionp (region-beginning) (line-beginning-position)))
         (end (if regionp (region-end) (progn (forward-line 1) (point)))))
    (kill-region beg end)
    (message "已剪切%s" (if regionp "选区" "当前行"))))

;; 搜索入口：rg 可用走 consult-ripgrep，缺失降级 consult-line
(declare-function consult-ripgrep "consult")
(declare-function consult-line "consult")
(defun custom/touch-search ()
  "搜索。rg 可用时全文检索，否则检索当前缓冲区。"
  (interactive)
  (if (executable-find "rg")
      (call-interactively #'consult-ripgrep)
    (call-interactively #'consult-line)))

;; ─── modifier-bar 开关 / 打开配置（tool-bar 首尾按钮的命令） ────────

(defun custom/touch-toggle-modifier-bar ()
  "显示/隐藏官方修饰键栏。"
  (interactive)
  (if (fboundp 'modifier-bar-mode)
      (modifier-bar-mode 'toggle)
    (message "本 Emacs 无 modifier-bar（需 Android 官方构建）")))

;; ─── modifier-bar 追加 Tab/ESC 按钮 ────────────────────────────────
;; 按钮集合即 secondary-tool-bar-map（Emacs 30 通用机制，可整体重建）；
;; TAB/ESC 非修饰键，塞进 unread-command-events 即等同物理按键。

(defun custom/modbar-tab ()  "发送 TAB 键（等同物理键盘 Tab）。"
  (interactive)
  (setq unread-command-events (list ?\t)))

(defun custom/modbar-esc ()
  "发送 ESC 键（取消补全/前缀键等）。"
  (interactive)
  (setq unread-command-events (list ?\e)))

(defun custom/modbar--badge (name)
  "取 data/icons/mod-NAME 徽章图像。
PBM 位图优先（官方修饰键同机制，按工具栏前景色着色、深浅主题自动
适配；PNG alpha 在 Lucid 露白底，仅兜底）。
位图不支持运行时缩放，尺寸烤在资产（字母 32×32、Tab/Esc 64×32）。"
  (find-image
   `((:type pbm :file ,(concat "mod-" name ".pbm"))
     (:type png :file ,(concat "mod-" name ".png")))))

(defun custom/modbar--setup ()
  "整套重建 modifier-bar：六修饰键 + Tab/ESC 统一为文字徽章风格
（官方原图是 35×19 PBM 徽章，风格不搭）。
`modifier-bar-mode' 每次开启都会重置该 map，须在其后调用。"
  (when (and (bound-and-true-p modifier-bar-mode)
             (fboundp 'modifier-bar-available-p))
    (setq secondary-tool-bar-map
          `(keymap
            (control menu-item "Control Key" event-apply-control-modifier
                     :help "Add Control modifier to the following event"
                     :image ,(custom/modbar--badge "control")
                     :enable (modifier-bar-available-p 'control))
            (shift menu-item "Shift Key" event-apply-shift-modifier
                   :help "Add Shift modifier to the following event"
                   :image ,(custom/modbar--badge "shift")
                   :enable (modifier-bar-available-p 'shift))
            (meta menu-item "Meta Key" event-apply-meta-modifier
                  :help "Add Meta modifier to the following event"
                  :image ,(custom/modbar--badge "meta")
                  :enable (modifier-bar-available-p 'meta))
            (alt menu-item "Alt Key" event-apply-alt-modifier
                 :help "Add Alt modifier to the following event"
                 :image ,(custom/modbar--badge "alt")
                 :enable (modifier-bar-available-p 'alt))
            (super menu-item "Super Key" event-apply-super-modifier
                   :help "Add Super modifier to the following event"
                   :image ,(custom/modbar--badge "super")
                   :enable (modifier-bar-available-p 'super))
            (hyper menu-item "Hyper Key" event-apply-hyper-modifier
                   :help "Add Hyper modifier to the following event"
                   :image ,(custom/modbar--badge "hyper")
                   :enable (modifier-bar-available-p 'hyper))
            (tab menu-item "TAB Key" custom/modbar-tab
                 :help "发送 TAB 键"
                 :image ,(custom/modbar--badge "tab"))
            (esc menu-item "ESC Key" custom/modbar-esc
                 :help "发送 ESC 键"
                 :image ,(custom/modbar--badge "esc"))))
    ;; 重建后刷掉 tool-bar 键映射缓存（按 map 身份哈希缓存）
    (when (fboundp 'tool-bar--flush-cache)
      (tool-bar--flush-cache))
    (force-mode-line-update t)))

(defun custom/touch-open-config ()
  "打开配置所在的文件夹（dired）。"
  (interactive)
  (dired user-emacs-directory))

(defconst custom/touch-storage-root "/storage/emulated/0/"
  "共享存储根（Android 用户数据区，= /sdcard）。")

(defun custom/touch-find-file ()
  "打开文件：默认落点强制为共享存储根。
启动期 buffer 在 setq-default 前已持有 ~，须显式绑定。"
  (interactive)
  (let ((default-directory
          (if (file-directory-p custom/touch-storage-root)
              custom/touch-storage-root
            default-directory)))
    (call-interactively #'find-file)))

(defun custom/touch-no-keyboard ()
  "buffer-local 关闭 tap 弹虚拟键盘（展示型 buffer 用）。"
  (setq-local touch-screen-display-keyboard nil))

(defun custom/touch-show-keyboard ()
  "主动唤出系统虚拟键盘（无软键盘的平台为空操作）。"
  (when (fboundp 'frame-toggle-on-screen-keyboard)
    (frame-toggle-on-screen-keyboard (selected-frame) nil)))

;; ─── Android 触屏特化 ───────────────────────────────────────────────

(when custom:android-p
  ;; 打开文件/文件夹的默认落点 = 共享存储根（授权「所有文件访问」后
  ;; 可读写；文件 buffer 仍默认到自身所在目录，行为不变）
  (when (file-directory-p "/storage/emulated/0/")
    (setq-default default-directory "/storage/emulated/0/")
    ;; 启动期 buffer 已持有旧值，补齐局部值
    (dolist (buf (buffer-list))
      (unless (buffer-local-value 'buffer-file-name buf)
        (with-current-buffer buf
          (setq default-directory "/storage/emulated/0/")))))

  ;; 触屏选项：tap 任意处可唤出系统虚拟键盘
  (setq touch-screen-display-keyboard t
        touch-screen-preview-select t
        touch-screen-word-select t
        touch-screen-extend-selection t)

  ;; 展示型 read-only buffer 内 tap 也弹键盘，逐 buffer 停用
  (dolist (hook '(dashboard-mode-hook eww-mode-hook nov-mode-hook
                   Info-mode-hook help-mode-hook
                   org-agenda-mode-hook dired-mode-hook))
    (add-hook hook #'custom/touch-no-keyboard))

  ;; dired tap 文件名（转 mouse-2）默认 other-window 打开会分屏，
  ;; 改为当前窗打开（目录同理）
  (with-eval-after-load 'dired
    (define-key dired-mode-map [mouse-2] #'dired-mouse-find-file))

  ;; 响铃以振动实现，默认时长偏长，调短（10–1000ms）
  (when (boundp 'android-keyboard-bell-duration)
    (setq android-keyboard-bell-duration 30))

  ;; 触屏无菜单交互，关闭菜单栏（命令走 tool-bar / M-x）
  (menu-bar-mode -1)

  ;; 修饰键交官方 modifier-bar，默认开（tool-bar 首位按钮可开关）。
  ;; 本模块先于 init-bar 加载，image-load-path 未就位，setup 须延迟到
  ;; init-bar 之后执行
  (when (fboundp 'modifier-bar-mode)
    (modifier-bar-mode 1)
    (advice-add 'modifier-bar-mode :after
                (lambda (&rest _) (custom/modbar--setup)))
    (with-eval-after-load 'init-bar
      (custom/modbar--setup))))

(provide 'init-touch)
;;; init-touch.el ends here
