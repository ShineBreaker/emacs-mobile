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

(use-package which-key
  :custom (which-key-idle-delay 0.6)
          ;; 底部弹窗（触屏视线近）
          (which-key-side-window-location 'bottom)
          ;; 侧窗加高 + 描述压缩：窄屏一屏容纳更多条目，减少翻页
          (which-key-side-window-max-height 0.5)
          (which-key-max-description-length 16)
          ;; 多层前缀启用官方 paging：弹窗内 C-h n/p 翻页（mode-line
          ;; 「»」按钮为触摸翻页入口，见 init-ui.el）
          (which-key-paging-prefixes '("C-x" "C-c" "C-h" "M-s" "M-g"))
  :config
  (custom/which-key-apply-descriptions)
  ;; 延迟到启动完成后开启，避免拖慢 init
  (add-hook 'emacs-startup-hook #'which-key-mode))

(provide 'init-completion)
;;; init-completion.el ends here
