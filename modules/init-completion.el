;;; init-completion.el --- 补全栈 + which-key 中文描述 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; vertico + orderless + marginalia + consult + embark + corfu（触屏可点选），
;; which-key 延迟到启动完成后开启，中文描述数据从桌面移植（data/which-key-zh.el）。

;;; Code:

;; ─── minibuffer 补全：vertico / orderless / marginalia ──────────────

(use-package vertico
  :init (vertico-mode)
  :custom (vertico-resize t))

(use-package orderless
  :custom (completion-styles '(orderless basic)))

(use-package marginalia
  :init (marginalia-mode))

;; ─── 搜索/导航：consult ─────────────────────────────────────────────

(use-package consult
  :custom (xref-show-xrefs-function #'consult-xref)
          (xref-show-definitions-function #'consult-xref))

;; ─── 上下文动作：embark ─────────────────────────────────────────────

(use-package embark
  :bind (("C-." . embark-act)))

(use-package embark-consult
  :after (embark consult))

;; ─── 行内补全：corfu + cape ─────────────────────────────────────────

(use-package corfu
  :init (global-corfu-mode)
  :custom (corfu-auto t)
          (corfu-cycle t))

(use-package cape
  :after corfu
  :init
  (add-to-list 'completion-at-point-functions #'cape-file))

;; ─── which-key + 中文描述 ───────────────────────────────────────────

;; 本地化数据文件只赋值，由下面的展开机制消费（从桌面移植）
(defvar custom:which-key-description-spec nil
  "which-key 键描述嵌套规格（data/which-key-zh.el 赋值）。")
(defvar custom:which-key-major-mode-description-spec nil
  "which-key 主模式键描述规格。")
(defvar custom:which-key-regexp-replacements nil
  "which-key 正则替换规则。")

(defvar which-key-replacement-alist nil)  ; which-key.el
(declare-function which-key-add-key-based-replacements "which-key")
(declare-function which-key-add-major-mode-key-based-replacements "which-key")

(defun custom/which-key--join-key (prefix key)
  "将 PREFIX 与 KEY 合并为 which-key 可用的键序列字符串。"
  (if (and prefix (> (length prefix) 0))
      (concat prefix " " key)
    key))

(defun custom/which-key--flatten-spec (prefix spec)
  "将 PREFIX 下的单个 SPEC 展开为 ((key . desc) ...) 列表。"
  (pcase spec
    (`(,key ,desc . ,children)
     (let ((full-key (custom/which-key--join-key prefix key)))
       (append (list (cons full-key desc))
               (custom/which-key--flatten-specs full-key children))))
    (`(,key . ,desc)
     (list (cons (custom/which-key--join-key prefix key) desc)))
    (_
     (error "无法识别的 which-key 描述项: %S" spec))))

(defun custom/which-key--flatten-specs (prefix specs)
  "将 PREFIX 下的 SPECS 展开为平铺的 ((key . desc) ...) 列表。"
  (apply #'append
         (mapcar (lambda (spec)
                   (custom/which-key--flatten-spec prefix spec))
                 specs)))

(defun custom/which-key-apply-descriptions ()
  "将中文描述注册到 `which-key'。"
  (let ((file (expand-file-name "data/which-key-zh.el"
                                user-emacs-directory)))
    (load file nil 'nomessage)
    (setq which-key-replacement-alist
          (append which-key-replacement-alist
                  custom:which-key-regexp-replacements))
    (dolist (entry (custom/which-key--flatten-specs
                    nil custom:which-key-description-spec))
      (which-key-add-key-based-replacements (car entry) (cdr entry)))
    (dolist (mode-entry custom:which-key-major-mode-description-spec)
      (dolist (entry (custom/which-key--flatten-specs
                      nil (cdr mode-entry)))
        (which-key-add-major-mode-key-based-replacements
          (car mode-entry) (car entry) (cdr entry))))))

(defun custom/which-key-next-page ()
  "which-key 弹窗显示时翻到下一页（mode-line 按钮用），无弹窗时无操作。"
  (interactive)
  (when (and (fboundp 'which-key--popup-showing-p)
             (which-key--popup-showing-p)
             (fboundp 'which-key-show-next-page-cycle))
    (which-key-show-next-page-cycle)))

;; ─── 弹窗内翻页按钮（触屏无 C-h；tap 触发 text-property keymap） ──

(defvar which-key--buffer nil)  ; which-key.el
(defvar which-key--pages-obj nil)  ; which-key.el
(declare-function which-key-show-next-page-cycle "which-key")
(declare-function which-key-show-previous-page-cycle "which-key")
(declare-function which-key--pages-pages "which-key")

(defun custom/which-key--page-button (label command)
  "弹窗翻页按钮文本（[] 胶囊风格，与 dashboard 一致）。"
  (concat
   (propertize "[" 'face 'shadow)
   (propertize (format " %s " label)
               'keymap (let ((map (make-sparse-keymap)))
                         (define-key map [mouse-1] command)
                         map)
               'mouse-face 'highlight
               'follow-link t)
   (propertize "]" 'face 'shadow)))

(defun custom/which-key--insert-buttons-into-buffer ()
  "向 which-key buffer 末尾追加居中翻页按钮行（不动窗口）。"
  (with-current-buffer which-key--buffer
    (let* ((inhibit-read-only t)
           (btns (concat (custom/which-key--page-button
                          "上一页" #'which-key-show-previous-page-cycle)
                         "  "
                         (custom/which-key--page-button
                          "下一页" #'which-key-show-next-page-cycle))))
      (goto-char (point-max))
      (insert "\n"
              (make-string (max 0 (/ (- (frame-width) (string-width btns)) 2))
                           ?\s)
              btns))))

(defun custom/which-key--popup-with-buttons (orig dim)
  "多页时注入翻页按钮行并计入弹窗高度（fit 之前注入才可见）。"
  (when (and which-key--pages-obj
             (> (length (which-key--pages-pages which-key--pages-obj)) 1))
    (custom/which-key--insert-buttons-into-buffer)
    (setcar dim (1+ (car dim))))
  (funcall orig dim))

(advice-add 'which-key--show-popup :around
            #'custom/which-key--popup-with-buttons)

(use-package which-key
  :defer t
  :custom (which-key-idle-delay 0.6)
          ;; 底部弹窗（触屏视线近）
          (which-key-side-window-location 'bottom)
          (which-key-side-window-max-height 0.5)
          (which-key-min-display-lines 10)
          ;; 窄屏布局：描述 20 列（40 列窗单列上限，28 会让列宽计算
          ;; 出负数崩渲染），列内对齐
          (which-key-max-description-length 20)
          (which-key-min-column-description-width 16)
          (which-key-add-column-padding 1)
          ;; 一条目允许多条替换规则链式应用（前缀组名与叶子名都替换）
          (which-key-allow-multiple-replacements t)
          (which-key-sort-order #'which-key-prefix-then-key-order)
          ;; 触屏无 C-h：关 C-h 分发（页脚键位提示随之消失），翻页走弹窗按钮
          (which-key-use-C-h-commands nil)
          ;; 多层前缀启用官方 paging（翻页按钮依赖其分页状态）
          (which-key-paging-prefixes '("C-x" "C-c" "C-h" "M-s" "M-g"))
  :init
  ;; 空闲才加载并开启：包加载与中文描述注册不占启动时间
  (run-with-idle-timer 1 nil #'which-key-mode)
  :config
  (custom/which-key-apply-descriptions))

(provide 'init-completion)
;;; init-completion.el ends here
