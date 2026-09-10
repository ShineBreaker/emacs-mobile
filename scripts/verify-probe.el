;;; verify-probe.el --- 交付前验证：启动后路径探针 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; `just verify' 的第三段：batch 冒烟不会触发 `emacs-startup-hook'，
;; 且 Android 专属分支被 `custom:android-p' 守卫跳过，dashboard 首屏
;; 生成、tool-bar 按钮安装、图标资产解析这些路径在桌面验证中从不运行。
;; 本探针显式调用它们。
;;
;; 结论以哨兵行输出，不依赖退出码：Guix 的 emacs 是 Guile wrapper，
;; 任何错误的退出码都会被吞成 0；wrapper 只保留执行流，故调用方必须
;; 检查 `VERIFY-PROBE-OK' 是否出现（缺哨兵即失败）。
;;
;; 用法: emacs --batch -l scripts/verify-probe.el

;;; Code:

(let* ((repo (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name))))))
  (setq user-emacs-directory repo)
  (condition-case err
      (progn
        (load (expand-file-name "early-init.el" repo))
        (add-to-list 'load-path (expand-file-name "modules" repo))
        (dolist (m '(init-basis init-packages init-ui init-touch init-bar
                     init-completion init-org init-markdown init-dashboard
                     init-reading init-misc))
          (require m))

        ;; 1) 图标资产：tool-bar 10 键 + modifier-bar 8 徽章全部可解析
        ;;    （SVG 重着色 / PBM 徽章 / PNG 兜底回退链，见 custom/icon-asset）
        (let ((missing nil))
          (dolist (k '(modbar open save copy paste cut search theme config quick))
            (unless (custom/icon-asset (symbol-name k) nil custom/bar-icon-height
                                       custom/bar-icon-color-light)
              (push k missing)))
          (dolist (k '(control shift meta alt super hyper tab esc))
            (unless (custom/icon-asset k t) (push k missing)))
          (when missing
            (error "图标资产缺失: %S（跑 `just icons' 重建）" (nreverse missing))))

        ;; 2) 仪表盘首屏数据：列笔记目录 + 读文件头 #+title:
        (custom/dashboard--recent-roam-files 5)

        ;; 3) Android 专属 tool-bar 安装（桌面 init 不执行，显式跑一遍）
        ;;    断言顺序（keymap 逆序存储，install 末尾反转，真机曾反馈顺序反了）、
        ;;    图标高度契约、SVG 重着色按主题生效
        (custom/bar--install)
        (let* ((bindings (cdr tool-bar-map))
               (expected '(modbar open save copy paste cut search theme config quick))
               (keys (mapcar #'car bindings)))
          (unless (equal keys expected)
            (error "tool-bar 顺序异常: %S（期望 %S）" keys expected))
          (dolist (k expected)
            (let* ((mi (cdr (assq k bindings)))
                   (img (plist-get (nthcdr 3 mi) :image)))
              (unless img (error "tool-bar %s 缺少图标" k))
              (unless (equal custom/bar-icon-height (image-property img :height))
                (error "tool-bar %s 图标高度 %S（期望 %d）"
                       k (image-property img :height) custom/bar-icon-height))))
          (when (image-type-available-p 'svg)
            (dolist (color (list custom/bar-icon-color-light custom/bar-icon-color-dark))
              (let ((data (image-property
                           (custom/icon-asset "open" nil custom/bar-icon-height color)
                           :data)))
                (unless (and data (string-match-p (regexp-quote color) data))
                  (error "SVG 重着色未生效：%s 的数据里找不到颜色 %s" "open" color))))))

        ;; 4) dired 下右端钮组省略首项 M-x（40 列窄屏给文件操作钮留宽）
        (let ((normal (string-width (custom/mode-line--buttons)))
              (dired (with-temp-buffer
                       (setq major-mode 'dired-mode)
                       (string-width (custom/mode-line--buttons)))))
          (unless (< dired normal)
            (error "dired 下 M-x 钮未过滤：常规 %d 列 vs dired %d 列"
                   normal dired)))

        ;; 5) which-key 开启兜底必需：Android 下 idle timer 疑不触发，
        ;;    只挂 idle 会让 which-key 与其触屏翻页钮一起永久失效
        (custom/which-key-ensure)
        (unless (bound-and-true-p which-key-mode)
          (error "custom/which-key-ensure 调用后 which-key-mode 仍未开启"))

        ;; 6) mode-line 右端只构造一次按钮串：弹性空格与按钮串合并为单个
        ;;    :eval（原先是两个，每次重绘把整组按钮连同 mouse-map 构造两遍）
        (let* ((n 0)
               (counter (lambda (&rest _) (cl-incf n))))
          (advice-add #'custom/mode-line--buttons :before counter)
          (unwind-protect
              (progn
                (custom/mode-line--right-part)
                (unless (= n 1)
                  (error "custom/mode-line--right-part 构造按钮串 %d 次（应 1 次）" n)))
            (advice-remove #'custom/mode-line--buttons counter)))

        (message "VERIFY-PROBE-OK 图标 18/18、仪表盘数据、tool-bar 10 钮、dired 钮组收缩、which-key 兜底、mode-line 单次构造"))
    (error
     (message "VERIFY-PROBE-FAIL %s" (error-message-string err))
     (kill-emacs 1))))

;;; verify-probe.el ends here
