# Xoderony

个人博客，托管在 [GitHub Pages](https://xoderony.github.io)，用 **Jekyll** 构建。

## 怎么更新文章（不需要本地工具）

1. 打开仓库：<https://github.com/Xoderony/Xoderony.github.io>
2. 进入 `_posts/` 目录，点 **Add file → Create new file**
3. 文件名格式：`YYYY-MM-DD-英文或拼音标题.md`  
   例如：`2026-07-31-my-new-post.md`
4. 内容写成：

```markdown
---
title: "文章标题"
date: 2026-07-31 12:00:00 +0800
tags:
  - 知识
---

这里写正文，支持 Markdown。
```

5. 提交（Commit）后，等一两分钟，打开 <https://xoderony.github.io> 即可看到新文章。

也可在 GitHub 网页上直接编辑已有 `_posts` 里的 `.md` 文件。

## 仓库设置（只需做一次）

GitHub 仓库 → **Settings → Pages**：

- Source：Deploy from a branch
- Branch：`main`（或你的默认分支），目录 `/ (root)`

仓库名需为 `Xoderony.github.io`（若仍是旧名，在 Settings → General 里改掉）。

GitHub 会自动用 Jekyll 构建，无需 Action、无需本机安装 Node / Hexo / Ruby。

## 目录说明

| 路径 | 作用 |
|------|------|
| `_posts/` | 文章（Markdown） |
| `_layouts/` / `_includes/` / `assets/` | 站点模板与样式 |
| `_config.yml` | 站点标题、作者等配置 |
| `about.md` | 关于页 |

## 可选：本机预览

若以后想在本机预览，可安装 Ruby 后执行：

```bash
bundle install
bundle exec jekyll serve
```

日常写文章不需要这一步。
