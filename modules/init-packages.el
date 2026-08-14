;;; init-packages.el --- straight.el 包管理与国内镜像三层 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Android 无 Guix，桌面配置的包管理改用 straight.el。
;; 镜像三层（PLAN §6）：
;;   1. ELPA/MELPA 归档镜像（package.el fallback）
;;   2. straight recipe 仓库官方 elpa mirror
;;   3. GitHub 加速代理（前缀式，可选，默认关闭；仅作用于 bootstrap 脚本下载，
;;      git clone 加速待真机验证后实现）

;;; Code:

;; ─── 镜像配置变量（顶部可切换） ───────────────────────────────────────

(defcustom custom/elpa-mirror 'tuna
  "ELPA/MELPA 镜像源：\\='tuna | \\='ustc | nil（官方源）。"
  :type '(choice (const :tag "TUNA" tuna)
                 (const :tag "USTC" ustc)
                 (const :tag "官方" nil))
  :group 'emacs-mobile)

(defcustom custom/github-proxy nil
  "GitHub 加速代理前缀（如 \"https://ghproxy.com/\"），nil 表示直连。
仅作用于 straight bootstrap 安装脚本的下载 URL；
git clone 层面的加速待真机验证后实现（见 PLAN §15）。"
  :type '(choice (const :tag "直连" nil)
                 (string :tag "代理前缀"))
  :group 'emacs-mobile)

;; ─── straight bootstrap ─────────────────────────────────────────────

(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el"
                         user-emacs-directory))
      (bootstrap-version 7)
      ;; 第 3 层：bootstrap 安装脚本 URL 走前缀代理（仅首次下载生效）
      (install-url
       (concat (or custom/github-proxy "")
               "https://raw.githubusercontent.com/radian-software/straight.el/master/install.el")))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously install-url 'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

;; 消除 byte-compile 对 free variable 赋值的告警（实际由 straight bootstrap 定义）
(defvar straight-use-package-by-default)
(defvar straight-check-for-modifications)
(defvar straight-vc-git-default-clone-depth)
(defvar straight-recipes-gnu-elpa-use-mirror)
(defvar straight-recipes-nongnu-elpa-use-mirror)
(defvar straight-recipes-melpa-use-mirror)

;; Android 启动速度优先：跳过修改检查 + 浅克隆
(setq straight-use-package-by-default t
      straight-check-for-modifications '()
      straight-vc-git-default-clone-depth 1)

;; ─── 第 2 层：straight recipe 仓库走官方 elpa mirror ────────────────

(setq straight-recipes-gnu-elpa-use-mirror t
      straight-recipes-nongnu-elpa-use-mirror t
      straight-recipes-melpa-use-mirror t)

;; ─── 第 1 层：package-archives 镜像（package.el fallback） ──────────

(defvar package-archives)  ; built-in package.el

(setq package-archives
      (pcase custom/elpa-mirror
        ('tuna '(("gnu"    . "https://mirrors.tuna.tsinghua.edu.cn/elpa/gnu/")
                 ("nongnu" . "https://mirrors.tuna.tsinghua.edu.cn/elpa/nongnu/")
                 ("melpa"  . "https://mirrors.tuna.tsinghua.edu.cn/elpa/melpa/")))
        ('ustc '(("gnu"    . "https://mirrors.ustc.edu.cn/elpa/gnu/")
                 ("nongnu" . "https://mirrors.ustc.edu.cn/elpa/nongnu/")
                 ("melpa"  . "https://mirrors.ustc.edu.cn/elpa/melpa/")))
        (_ '(("gnu"    . "https://elpa.gnu.org/packages/")
             ("nongnu" . "https://elpa.nongnu.org/nongnu/")
             ("melpa"  . "https://melpa.org/packages/")))))

(provide 'init-packages)
;;; init-packages.el ends here
