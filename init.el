;;; init.el --- emacs-mobile 入口，按序加载各模块 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 固定入口，仅将 modules/ 加入 load-path 并按序 require。
;; 模块顺序即依赖顺序：basis → packages → 其余。
;;
;; 真机部署：本文件与 early-init.el 复制到 Emacs 的 ~/.emacs.d，完整
;; 仓库在 Termux home。early-init 已重定向 `user-emacs-directory'，
;; load-path/require 随之指向仓库 modules；若 early-init 未运行（副本
;; 缺失/旧版），此处自行重定向并转发到仓库 init.el。
;;
;; 加载失败时先看 `M-x custom/deploy-diagnose' 的诊断结论。

;;; Code:

(defvar custom:termux-repo)  ; 唯一定义在 early-init.el（必然先于本文件运行）

;; ─── 部署诊断（不依赖 modules，require 失败后仍可用） ─────────────

(defun custom/deploy--termux-home-p ()
  "Termux home 是否可被 Emacs 访问（签名兼容/sharedUserId 是否生效）。"
  (file-directory-p "/data/data/com.termux/files/home"))

(defun custom/deploy--conclusion ()
  "返回针对当前状态的诊断结论字符串。"
  (cond
   ((not (eq system-type 'android))
    "桌面环境：无 Termux 部署链路，modules 应在 user-emacs-directory 下。")
   ((not (boundp 'custom:termux-repo))
    "early-init.el 副本过旧或缺失（custom:termux-repo 未定义）：\n  重新复制两个入口文件（README §4）。")
   ((not (custom/deploy--termux-home-p))
    (concat "Emacs 无法访问 Termux home（/data/data/com.termux/files/home）：\n"
            "  签名兼容未生效或 Termux 未安装。按 README §2 完成重签流程后重试。"))
   ((not (file-directory-p custom:termux-repo))
    (format "Termux home 可读，但仓库 %s 不存在：\n  检查 git clone 位置与目录名。" custom:termux-repo))
   ((not (file-directory-p (expand-file-name "modules" custom:termux-repo)))
    (format "仓库存在但缺少 modules/ 目录：\n  clone 不完整，重新拉取 %s。" custom:termux-repo))
   ((not (file-equal-p user-emacs-directory custom:termux-repo))
    (concat "仓库可达，但 user-emacs-directory 未重定向到仓库：\n"
            "  Emacs home 的 early-init.el 是旧版或未复制，重新复制两个入口文件（README §4）。"))
   (t "部署链路正常。")))

(defun custom/deploy-diagnose ()
  "弹出 buffer 显示真机部署链路诊断与结论。"
  (interactive)
  (let ((buf (get-buffer-create "*emacs-mobile 部署诊断*"))
        (repo (and (boundp 'custom:termux-repo) custom:termux-repo)))
    (with-current-buffer buf
      (fundamental-mode)
      (erase-buffer)
      (insert
       (format
        "system-type:            %S
window-system:          %S
user-emacs-directory:   %s
user-init-file:         %s
custom:termux-repo:     %s
  仓库存在:             %s
  仓库 modules 存在:    %s
Termux home 可访问:     %s
Termux bin 存在:        %s
modules 在 load-path:   %s
sqlite3 CLI 可用:       %s   ; org-roam 依赖（CLI 后端）
ripgrep (rg) 可用:      %s
native-comp 可用:       %S
org 目录存在:           %s

结论:
%s"
        system-type (window-system)
        user-emacs-directory (or user-init-file "(未记录)")
        (or repo "(未定义)")
        (and repo (file-directory-p repo))
        (and repo (file-directory-p (expand-file-name "modules" repo)))
        (custom/deploy--termux-home-p)
        (file-directory-p "/data/data/com.termux/files/usr/bin")
        (and (member (expand-file-name "modules" user-emacs-directory)
                     load-path)
             t)
        (executable-find "sqlite3")
        (executable-find "rg")
        (native-comp-available-p)
        (if (and (boundp 'custom:org-directory)
                 custom:org-directory)
            (format "%s (%s)" custom:org-directory
                    (if (file-directory-p custom:org-directory) "存在" "不存在"))
          "(custom:org-directory 未定义，modules 未加载?)")
        (custom/deploy--conclusion)))
      (goto-char (point-min)))
    (pop-to-buffer buf)))

;; ─── 入口：转发或本体 ───────────────────────────────────────────────

(if (and (boundp 'custom:termux-repo)
         (eq system-type 'android)
         (file-directory-p (expand-file-name "modules" custom:termux-repo))
         (not (file-equal-p user-emacs-directory custom:termux-repo)))
    ;; user-emacs-directory 未经 early-init 重定向：手动转发
    (progn
      (setq user-emacs-directory custom:termux-repo)
      (load (expand-file-name "init.el" custom:termux-repo) nil t))

  ;; Android 上 modules 缺失时给出有信息量的错误
  ;; （而非 Cannot open load file: init-basis）
  (when (and (eq system-type 'android)
             (not (file-directory-p
                   (expand-file-name "modules" user-emacs-directory))))
    (error "emacs-mobile: modules 不可用。%s"
           (custom/deploy--conclusion)))

  (add-to-list 'load-path (expand-file-name "modules" user-emacs-directory))

  (require 'init-basis)
  (require 'init-packages)
  (require 'init-ui)
  (require 'init-touch)
  (require 'init-bar)
  (require 'init-completion)
  (require 'init-org)
  (require 'init-markdown)
  (require 'init-dashboard)
  (require 'init-reading)
  (require 'init-misc))

;;; init.el ends here
