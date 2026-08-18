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
(declare-function custom/icon-asset "init-basis")
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

;; ─── 触屏确认面板（widget 是/否，替代键盘 y-or-n） ─────────────────

(defvar custom/touch-confirm-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'widget-button-click)
    (define-key map [touchscreen-begin] #'widget-button-click)
    map))

(define-derived-mode custom/touch-confirm-mode special-mode "确认"
  "触屏确认面板。"
  (setq-local touch-screen-display-keyboard nil))

(defun custom/touch-confirm (title action)
  "当前窗弹确认面板：TITLE 提示，点「确认」执行 ACTION（零参函数）。"
  (switch-to-buffer (get-buffer-create "*确认*"))
  (custom/touch-confirm-mode)
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert "\n  " (propertize title 'face 'bold) "\n\n  ")
    (widget-create 'item
                   :tag " 确认 "
                   :action (lambda (&rest _) (kill-buffer) (funcall action))
                   :button-face 'bold
                   :mouse-face 'highlight
                   :button-prefix "" :button-suffix ""
                   :format "%[%t%]")
    (insert "    ")
    (widget-create 'item
                   :tag " 取消 "
                   :action (lambda (&rest _) (kill-buffer))
                   :button-face 'shadow
                   :mouse-face 'highlight
                   :button-prefix "" :button-suffix ""
                   :format "%[%t%]")
    (goto-char (point-min))))

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
                     :image ,(custom/icon-asset "control" t)
                     :enable (modifier-bar-available-p 'control))
            (shift menu-item "Shift Key" event-apply-shift-modifier
                   :help "Add Shift modifier to the following event"
                   :image ,(custom/icon-asset "shift" t)
                   :enable (modifier-bar-available-p 'shift))
            (meta menu-item "Meta Key" event-apply-meta-modifier
                  :help "Add Meta modifier to the following event"
                  :image ,(custom/icon-asset "meta" t)
                  :enable (modifier-bar-available-p 'meta))
            (alt menu-item "Alt Key" event-apply-alt-modifier
                 :help "Add Alt modifier to the following event"
                 :image ,(custom/icon-asset "alt" t)
                 :enable (modifier-bar-available-p 'alt))
            (super menu-item "Super Key" event-apply-super-modifier
                   :help "Add Super modifier to the following event"
                   :image ,(custom/icon-asset "super" t)
                   :enable (modifier-bar-available-p 'super))
            (hyper menu-item "Hyper Key" event-apply-hyper-modifier
                   :help "Add Hyper modifier to the following event"
                   :image ,(custom/icon-asset "hyper" t)
                   :enable (modifier-bar-available-p 'hyper))
            (tab menu-item "TAB Key" custom/modbar-tab
                 :help "发送 TAB 键"
                 :image ,(custom/icon-asset "tab" t))
            (esc menu-item "ESC Key" custom/modbar-esc
                 :help "发送 ESC 键"
                 :image ,(custom/icon-asset "esc" t))))
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

;; dired 窄屏精简：隐藏权限/属主/大小/时间细节列，只留文件名
;;（完整 -l 格式 60+ 列，手机屏文件名必然折行）
(add-hook 'dired-mode-hook #'dired-hide-details-mode)

;; ─── dired 触屏操作：改名/删除走 minibuffer 点选，新建直接输入 ────
;; dired 里 tap 即打开文件，无「只选中不打开」交互；操作对象改由
;; minibuffer 补全列表（vertico 点选）指定。

(declare-function dired-revert "dired")
(declare-function dired-create-empty-file "dired")
(declare-function dired-create-directory "dired")
(declare-function dired-current-directory "dired")

(defun custom/dired-touch-rename ()
  "重命名：点选文件 → 输入新名。"
  (interactive)
  (let* ((dir (dired-current-directory))
         (old (read-file-name "重命名（点选文件）: " dir nil t))
         (new (read-file-name "新名字: " dir nil nil
                              (file-name-nondirectory old))))
    (unless (equal old new)
      (rename-file old new)
      (dired-revert))))

(defun custom/dired-touch-delete ()
  "删除：点选文件 → 确认面板 → 删除。"
  (interactive)
  (let* ((dir (dired-current-directory))
         (file (read-file-name "删除（点选文件）: " dir nil t)))
    (if (file-directory-p file)
        (message "暂不支持删除目录")
      (custom/touch-confirm
       (format "删除 %s ？" (file-name-nondirectory file))
       (lambda ()
         (delete-file file)
         (dired-revert))))))

(defun custom/dired--op-button (glyph fallback help command)
  "dired mode-line 操作按钮（四钮并排，间距 1 列保持紧凑）。"
  (propertize
   (format " %s" (custom/glyph glyph fallback))
   'local-map (make-mode-line-mouse-map 'mouse-1 command)
   'mouse-face 'highlight
   'help-echo help))

(defun custom/dired--op-buttons ()
  "dired 文件操作钮串：改名/删除/建文件/建目录。"
  (concat
   (custom/dired--op-button "\uF304" "改" "重命名（点选文件）"
                            #'custom/dired-touch-rename)
   (custom/dired--op-button "\uF1F8" "删" "删除（点选文件）"
                            #'custom/dired-touch-delete)
   (custom/dired--op-button "\uF15B" "文" "新建文件"
                            #'dired-create-empty-file)
   (custom/dired--op-button "\uF07B" "夹" "新建目录"
                            #'dired-create-directory)))

(defun custom/dired-setup-mode-line ()
  "dired buffer：mode-line 右端钮组前插入文件操作钮。"
  ;; mode-name 压缩（默认 \"Dired by name\" 太占宽，窄屏挤出按钮）
  (setq-local mode-name "Dired")
  (let* ((fmt (default-value 'mode-line-format))
         (pos (seq-position fmt '(:eval (custom/mode-line--right-space)))))
    (when pos
      (setq-local mode-line-format
                  (append (seq-take fmt pos)
                          (list '(:eval (custom/dired--op-buttons)))
                          (seq-drop fmt pos))))))

(add-hook 'dired-mode-hook #'custom/dired-setup-mode-line)

;; agenda 条目 tap（mouse-2）= 定位行 + 跳转源条目（编辑管理在 Orgzly，
;; Emacs 侧只读查看）
(defvar org-agenda-mode-map)  ; org-agenda.el
(declare-function org-agenda-switch-to "org-agenda")
(with-eval-after-load 'org-agenda
  (define-key org-agenda-mode-map [mouse-2]
    (lambda (e)
      "tap 条目行跳转源条目。"
      (interactive "e")
      (posn-set-point (event-start e))
      (org-agenda-switch-to))))

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
