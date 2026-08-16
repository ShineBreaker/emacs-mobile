;;; init-packages.el --- straight.el 包管理与国内镜像三层 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Android 无 Guix，包管理改用 straight.el。镜像三层：
;;   1. ELPA/MELPA 归档镜像（package.el fallback）
;;   2. straight recipe 仓库官方 elpa mirror
;;   3. GitHub 加速代理（可选，默认关闭；仅作用于 bootstrap 脚本下载）

;;; Code:

;; ─── 镜像配置变量（顶部可切换） ───────────────────────────────────────

(defcustom custom/elpa-mirror 'tuna
  "ELPA/MELPA 镜像源：\\='tuna | \\='ustc | nil（官方源）。"
  :type '(choice (const :tag "TUNA" tuna)
                 (const :tag "USTC" ustc)
                 (const :tag "官方" nil))
  :group 'emacs-mobile)  ; 组定义见 init-basis.el

(defcustom custom/github-proxy nil
  "GitHub 加速代理前缀（如 \"https://ghproxy.com/\"），nil 表示直连。
仅作用于 straight bootstrap 安装脚本的下载 URL。"
  :type '(choice (const :tag "直连" nil)
                 (string :tag "代理前缀"))
  :group 'emacs-mobile)

;; 缓存放 git 仓库外（custom:data-home，见 init-basis），避免克隆污染
;; 仓库目录、触发安全扫描误报。straight 在 base-dir 下自建 straight/
;; 子目录，故此处只到 ~/.cache/emacs/。
(defvar straight-base-dir)
(setq straight-base-dir
      (expand-file-name ".cache/emacs/" custom:data-home))

;; 须在 bootstrap 之前设置：否则按默认值每次启动跑 mtime find 检查
(defvar straight-use-package-by-default)
(defvar straight-check-for-modifications)
(defvar straight-vc-git-default-clone-depth)
(defvar straight-recipes-gnu-elpa-use-mirror)
(defvar straight-recipes-nongnu-elpa-use-mirror)
(defvar straight-recipes-melpa-use-mirror)

;; 启动速度优先：跳过修改检查 + 浅克隆
(setq straight-use-package-by-default t
      straight-check-for-modifications '()
      straight-vc-git-default-clone-depth 1)

;; ─── 第 2 层：straight recipe 仓库走官方 elpa mirror ────────────────

(setq straight-recipes-gnu-elpa-use-mirror t
      straight-recipes-nongnu-elpa-use-mirror t
      straight-recipes-melpa-use-mirror t)

;; ─── 版本 pin：straight versions lockfile ─────────────────────────────
;; straight recipe 不支持 :commit，pin 用 versions lockfile——bootstrap
;; 读取，克隆时强制 checkout。lockfile 仅克隆时生效，换版本需删除
;; <cache>/straight/repos/<repo> 后重启（或 M-x straight-thaw-versions）。
(defconst custom/straight-pinned-versions
  '(("org-roam" . "69116a4da49448e79ac03aedceeecd9f5ae9b2d4")  ; v2.2.2
    ("emacsql" . "c1a44076c0e44d5730b67b13c0e741f66f52fc85")  ; 3.1.1（tag 为 annotated，指向此 commit）
    ("emacsql-sqlite3" . "2113618732665f2112cb932a66c0e89c404d8777"))
  "锁定的包版本（repo 名 → commit）。
org-roam 2.3+ 的 emacsql 内置 sqlite 后端在 Android 不可用，须与
emacsql 3.x（sqlite3 CLI 后端）一同 pin，见 init-org.el。")

;; MELPA 已下架 emacsql-sqlite / emacsql-sqlite3 recipe（emacsql 4.x
;; 改名所致），org-roam 2.2.2 依赖查不到 → 手动注册：
;; · emacsql-sqlite：org-roam.el 顶层 require（仅加载定义，C 二进制不
;;   被编译/使用）；与 emacsql 同一仓库 → 共享上面的 pin。
;; · emacsql-sqlite3：sqlite3 CLI 后端（cireu 维护）。
;; · magit-section：显式锁 files 防镜像 recipe 漂移（缓存曾混入完整
;;   magit，加载后弹 Emergency：内置 transient 旧于 magit 要求）。
;;   magit 仓库源码在 lisp/ 子目录（files 误写根路径会静默 build 出
;;   空目录，straight 信任已存在目录不再重建）。已污染的缓存须删除
;;   重建（README §4）。
(defvar straight-recipe-overrides)
;; 键须为 profile 名（默认 profile 为 nil，非 :all）
(setq straight-recipe-overrides
      '((nil . ((emacsql-sqlite
                  :type git :host github :repo "magit/emacsql"
                  :files ("emacsql-sqlite.el"))
                 (emacsql-sqlite3
                  :type git :host github :repo "cireu/emacsql-sqlite3")
                 (magit-section
                  :type git :host github :repo "magit/magit"
                  :files ("lisp/magit-section.el"))))))

(let* ((lockfile (expand-file-name "straight/versions/default.el"
                                   straight-base-dir))
       (existing (when (file-exists-p lockfile)
                   (with-temp-buffer
                     (insert-file-contents lockfile)
                     (ignore-errors (read (current-buffer))))))
       (alist (copy-tree existing)))
  ;; 幂等合入，保留既有锁定条目
  (dolist (pin custom/straight-pinned-versions)
    (setf (alist-get (car pin) alist nil nil #'equal) (cdr pin)))
  ;; 内容无变化不写盘（省一次启动 IO）
  (unless (equal alist existing)
    (make-directory (file-name-directory lockfile) t)
    (with-temp-file lockfile
      (prin1 alist (current-buffer)))))

;; ─── straight bootstrap ─────────────────────────────────────────────

(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el"
                         straight-base-dir))
      (bootstrap-version 7)
      ;; bootstrap 安装脚本 URL 走前缀代理（仅首次下载生效）
      (install-url
       (concat (or custom/github-proxy "")
               "https://raw.githubusercontent.com/radian-software/straight.el/master/install.el")))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously install-url 'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

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
