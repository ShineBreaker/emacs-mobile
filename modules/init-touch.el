;;; init-touch.el --- 触屏层：官方 modifier-bar + 触屏编辑命令 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 2026-08-15 方案 F 拍板：交互组件全部回归官方宿主——
;; · 修饰键 → 官方 modifier-bar（tap 后下一个输入带修饰；自实现的
;;   tap 一次性 + 锁定 + key-translation 全套删除）
;; · 全局命令按钮 → 官方 tool-bar（init-bar.el 安装，底部）
;; · buffer/窗口控制 → mode-line（init-ui.el）
;; 自实现 side window bar（方案 E）废弃根因：tap 会把 bar 的 window
;; 选中，复制/剪切/撤销/切缓冲区等命令全部落到 *mobile-bar* 自身。

;;; Code:

(declare-function dashboard-open "dashboard")

;; ─── 复制 / 剪切：有选区作用于选区，无选区作用于当前行 ─────────────
;; 触屏长按拖选产生 region（真机实测），无选区时整行操作更符合触屏直觉。

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

;; ─── modifier-bar 追加 Tab/ESC 按钮（2026-08-16）──────────────────
;; modifier-bar 的按钮集合其实是 secondary-tool-bar-map（Emacs 30 通用
;; 机制，非上游写死，PLAN 旧结论「不可配」作废）；TAB/ESC 非修饰键，
;; 塞进 unread-command-events 即等同物理按键。

(defcustom custom/modbar-icon-height 28
  "modifier-bar 自定义按钮图标高度（对齐官方内置修饰键图标量级）。"
  :type 'integer
  :group 'emacs-mobile)

(declare-function custom/bar--svg-image "init-bar")

(defun custom/modbar-tab ()
  "发送 TAB 键（等同物理键盘 Tab：补全切换/缩进等场景）。"
  (interactive)
  (setq unread-command-events (list ?\t)))

(defun custom/modbar-esc ()
  "发送 ESC 键（取消补全/前缀键等）。"
  (interactive)
  (setq unread-command-events (list ?\e)))

(defun custom/modbar--setup ()
  "向 secondary-tool-bar-map 尾部追加 Tab/ESC 按钮（显示在修饰键右侧）。
`modifier-bar-mode' 每次开启都会重置该 map，须在其后调用。"
  (when (and (bound-and-true-p modifier-bar-mode)
             (boundp 'secondary-tool-bar-map)
             (keymapp secondary-tool-bar-map))
    (dolist (spec '((tab custom/modbar-tab "发送 TAB 键")
                    (esc custom/modbar-esc "发送 ESC 键")))
      (let ((key (nth 0 spec)) (cmd (nth 1 spec)) (help (nth 2 spec)))
        (define-key secondary-tool-bar-map (vector key)
          `(menu-item ,(upcase (symbol-name key)) ,cmd
                      :help ,help
                      :image ,(custom/bar--svg-image
                               (symbol-name key)
                               custom/modbar-icon-height)))))
    ;; define-key 插到列表头（显示会跑到修饰键左侧），移到尾部
    (let ((alist (cdr secondary-tool-bar-map)))
      (dolist (k '(tab esc))
        (let ((cell (assq k alist)))
          (setq alist (append (delq cell alist) (list cell)))))
      (setf (cdr secondary-tool-bar-map) alist))
    ;; 就地改动后必须刷掉 tool-bar 键映射缓存（按 map 身份哈希缓存）
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
default-directory 是 buffer 局部值，启动期生成的 buffer（scratch/
dashboard）在 setq-default 前已持有 ~，按钮侧显式绑定才可靠。"
  (interactive)
  (let ((default-directory
          (if (file-directory-p custom/touch-storage-root)
              custom/touch-storage-root
            default-directory)))
    (call-interactively #'find-file)))

(defun custom/touch-no-keyboard ()
  "buffer-local 关闭 tap 弹虚拟键盘（展示型 buffer 用）。"
  (setq-local touch-screen-display-keyboard nil))

;; ─── Android 触屏特化 ───────────────────────────────────────────────

(when custom:android-p
  ;; 打开文件/文件夹的默认落点 = 共享存储根（授权「所有文件访问」后
  ;; 可读写；scratch/dashboard 等无本地值的 buffer 继承此默认，
  ;; 文件 buffer 仍默认到自身所在目录，行为不变）
  (when (file-directory-p "/storage/emulated/0/")
    (setq-default default-directory "/storage/emulated/0/")
    ;; 启动期 buffer 在 setq-default 前已生成，补齐局部值（dired 等此后
    ;; 新 buffer 自然继承默认值）
    (dolist (buf (buffer-list))
      (unless (buffer-local-value 'buffer-file-name buf)
        (with-current-buffer buf
          (setq default-directory "/storage/emulated/0/")))))

  ;; 触屏选项：tap 任意处可唤出系统虚拟键盘
  (setq touch-screen-display-keyboard t
        touch-screen-preview-select t
        touch-screen-word-select t
        touch-screen-extend-selection t)

  ;; 全局 t 的副作用：展示型 read-only buffer 内 tap 也弹键盘（手册
  ;; 6.2：该变量支持 buffer-local，逐 buffer 停用）
  (dolist (hook '(dashboard-mode-hook eww-mode-hook nov-mode-hook
                   Info-mode-hook help-mode-hook))
    (add-hook hook #'custom/touch-no-keyboard))

  ;; 响铃以振动实现（手册 H.6），默认时长偏长，调短减少打扰（10–1000ms）
  (when (boundp 'android-keyboard-bell-duration)
    (setq android-keyboard-bell-duration 30))

  ;; 触屏无菜单交互场景，关闭菜单栏省一行（命令走 tool-bar / M-x）
  (menu-bar-mode -1)

  ;; 修饰键交官方 modifier-bar，默认开（tool-bar 首位按钮可开关）；
  ;; 每次开启后追加 Tab/ESC 自定义按钮（mode 会重置 map）
  (when (fboundp 'modifier-bar-mode)
    (modifier-bar-mode 1)
    (advice-add 'modifier-bar-mode :after
                (lambda (&rest _) (custom/modbar--setup)))
    (custom/modbar--setup)))

(provide 'init-touch)
;;; init-touch.el ends here
