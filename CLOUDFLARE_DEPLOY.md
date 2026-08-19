# LunaTV · Cloudflare Pages 部署指南

本指南介绍如何将 **LunaTV（MoonTV）** 部署到 [Cloudflare Pages](https://pages.cloudflare.com/)，
使用 [@cloudflare/next-on-pages](https://github.com/cloudflare/next-on-pages) 将 Next.js 应用跑在 Cloudflare 全球边缘网络，
并配套部署独立的代理 Worker（`proxy.worker.js`）。

> 部署思路参考 [LibreTV](https://github.com/thelosttimes/LibreTV) 的 Cloudflare Pages 方式。

---

## ⚠️ 重要前提

1. **存储只能用 Upstash**
   Cloudflare 运行时（Workers / Pages Functions）**不支持 TCP 连接**，因此 `redis` / `kvrocks` 无法使用。
   请使用 **Upstash（HTTPS REST）**：`NEXT_PUBLIC_STORAGE_TYPE=upstash` + `UPSTASH_URL` + `UPSTASH_TOKEN`。
2. **`NEXT_PUBLIC_*` 变量必须在「构建时」导出**，才会被内联进前端包。
   在脚本 / CI 中通过 shell `export` 设置；仅写在 `wrangler.toml [vars]` 只会在运行时生效，不会内联。
3. **定时任务（cron）** `/api/cron`（原 `vercel.json` 中的 `0 1 * * *`）在 Cloudflare Pages 上不会自动触发，
   请用外部定时任务（如 GitHub Actions `schedule` 或服务器 crontab）定时请求你的 `/api/cron` 接口。
4. 本项目不在中国大陆地区提供服务，请遵守当地法律法规。

---

## 一、准备

1. 注册 [Cloudflare](https://dash.cloudflare.com/) 账号，获取：
   - **Account ID**：右下角「账户 ID」
   - **API Token**：`My Profile → API Tokens → Create Token`，
     权限需包含 `Account > Cloudflare Pages > Edit` 以及 `Account > Workers Scripts > Edit`
     （或直接使用 **Edit Cloudflare Workers** 模板）。
2. 注册 [Upstash](https://upstash.com/) 并新建一个 Redis 数据库，复制：
   - **HTTPS Endpoint**（`UPSTASH_URL`，形如 `https://xxx.upstash.io`）
   - **Token**（`UPSTASH_TOKEN`）

---

## 二、本地一键部署（deploy-cloudflare.sh）

1. Fork / 克隆本仓库并进入目录。
2. （可选）创建 `.env.cloudflare` 存放配置：

   ```bash
   # Cloudflare
   CLOUDFLARE_API_TOKEN=你的令牌
   CLOUDFLARE_ACCOUNT_ID=你的账户ID

   # 管理员（必填）
   USERNAME=admin
   PASSWORD=你的强密码

   # Upstash 存储（必填）
   NEXT_PUBLIC_STORAGE_TYPE=upstash
   UPSTASH_URL=https://xxx.upstash.io
   UPSTASH_TOKEN=你的upstash_token

   # 可选站点配置
   NEXT_PUBLIC_SITE_NAME=LunaTV
   SITE_BASE=https://你的域名.pages.dev
   ANNOUNCEMENT=欢迎使用 LunaTV
   # NEXT_PUBLIC_DOUBAN_PROXY_TYPE=cmliussss-cdn-tencent
   # NEXT_PUBLIC_DOUBAN_IMAGE_PROXY_TYPE=cmliussss-cdn-tencent
   ```

3. 赋予执行权限并运行：

   ```bash
   chmod +x deploy-cloudflare.sh
   ./deploy-cloudflare.sh
   ```

   脚本会自动：安装 `wrangler` 与 `@cloudflare/next-on-pages` → 用 next-on-pages 构建 →
   部署到 Cloudflare Pages 项目 `lunatv` → 设置运行时机密 → 部署代理 Worker `lunatv-proxy`。

   > 未设置 `CLOUDFLARE_API_TOKEN` 时，脚本会引导你执行 `wrangler login`（交互式浏览器登录）。

跳过代理 Worker：`DEPLOY_PROXY_WORKER=false ./deploy-cloudflare.sh`

---

## 三、GitHub Actions 自动部署（推荐）

推送即部署：每次向 `main` 分支 push，都会自动构建并发布到 Cloudflare Pages。

1. 在本仓库的 **Settings → Secrets and variables → Actions** 中配置：
   - **Secrets**：`CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID`、`USERNAME`、`PASSWORD`、`UPSTASH_URL`、`UPSTASH_TOKEN`
   - **Variables**（可选，构建时内联）：`NEXT_PUBLIC_SITE_NAME`、`NEXT_PUBLIC_SEARCH_MAX_PAGE`、
     `NEXT_PUBLIC_FLUID_SEARCH`、`SITE_BASE`、`ANNOUNCEMENT`、
     `NEXT_PUBLIC_DOUBAN_PROXY_TYPE`、`NEXT_PUBLIC_DOUBAN_IMAGE_PROXY_TYPE`
2. 推送代码到 `main`，在 **Actions** 标签页查看部署进度。
3. 首次部署后，到 Cloudflare 面板 `Pages → lunatv → Settings → Builds & deployments`
   确认生产分支为 `main`。

> 工作流文件：`.github/workflows/deploy-cloudflare.yml`
> 所有机密通过 GitHub Secrets 注入，不会出现在代码或日志中。

---

## 四、自定义域名

1. Cloudflare 面板 `Pages → lunatv → Custom domains → Set up a custom domain`。
2. 或在 `wrangler.toml` 中设置 `SITE_BASE` 并在 DNS 添加 CNAME 指向 `*.pages.dev`。
3. 代理 Worker 自定义域名：编辑 `wrangler.proxy.toml` 的 `routes`。

---

## 五、文件说明

| 文件 | 作用 |
| --- | --- |
| `wrangler.toml` | Cloudflare Pages 项目配置（构建产物目录、运行时变量、兼容性） |
| `wrangler.proxy.toml` | 代理 Worker（`proxy.worker.js`）的独立配置 |
| `deploy-cloudflare.sh` | 本地一键部署脚本 |
| `.github/workflows/deploy-cloudflare.yml` | 推送即自动部署的 CI 工作流 |
| `next.config.js` | 已做兼容：`output: 'standalone'` 仅在非 Cloudflare 构建时启用 |

---

## 六、排错

- **构建报 `output: 'standalone' is not compatible`**
  → 确保构建时导出了 `NEXT_ON_PAGES=1`（脚本与 CI 已处理）。
- **页面空白 / 收藏不同步**
  → 确认 `NEXT_PUBLIC_STORAGE_TYPE=upstash` 且 `UPSTASH_URL` / `UPSTASH_TOKEN` 正确；
     `NEXT_PUBLIC_STORAGE_TYPE` 必须在构建时导出才会内联。
- **代理 Worker 跨域 / 403**
  → 检查 `wrangler.proxy.toml` 的 `routes`；Worker 默认已开启 CORS。
- **`wrangler` 命令找不到**
  → 本地执行 `npm i -g wrangler`；CI 中已自动安装。
- **Pages 部署提示 project not found**
  → 首次运行会自动创建项目 `lunatv`；也可在 Cloudflare 面板手动新建同名项目。
