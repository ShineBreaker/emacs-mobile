# emacs-mobile

Android 原生 Emacs（GNU Emacs 30.2+，包名 `org.gnu.emacs`）触屏优化配置：
以 Org 笔记与阅读为主用途，纯触屏 + `modifier-bar-mode` 交互。

> 设计依据见 PLAN.md（不入库）。

## 部署

待完善（Termux 签名、镜像源、权限授予、org-roam 重建等）。

## 沙箱测试（桌面开发期）

```sh
HOME=$(pwd)/.sandbox emacs --batch \
  --eval "(setq user-emacs-directory \"$(pwd)/\")" \
  -l early-init.el -l init.el
```

Android 特化模块整体 `(when (eq system-type 'android) ...)` 守卫，
桌面加载时自动跳过，因此完整配置在桌面沙箱内即可验证。
