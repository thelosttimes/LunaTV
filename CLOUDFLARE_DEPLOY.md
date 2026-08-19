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
   在 `wrangler.toml` 的 `[build] command` 中已默认导出；如需自定义，直接改那里的 export。
3. **定时任务（cron）** `/api/cron`（原 `vercel.json` 中的 `0 1 * * *`）在 Cloudflare Pages 上不会自动触发，
   请用外部定时任务（如 GitHub Actions `schedule` 或服务器 crontab）定时请求你的 `/api/cron` 接口。
4. 本项目不在中国大陆地区提供服务，请遵守当地法律法规。

---

## 一、准备

1. 注册 [Cloudflare](https://dash.cloudflare.com/) 账号，获取：
   - **Account ID**：右下角「账户 ID」
   - （仅本地 / Actions 部署需要）**API Token**：`My Profile → API Tokens → Create Token`，
     权限需包含 `Account > Cloudflare Pages > Edit` 以及 `Account > Workers Scripts > Edit`。
2. 注册 [Upstash](https://upstash.com/) 并新建一个 Redis 数据库，复制：
   - **HTTPS Endpoint**（`UPSTASH_URL`，形如 `https://xxx.upstash.io`）
   - **Token**（`UPSTASH_TOKEN`）

---

## 二、方式 A：Cloudflare Pages Git 集成（推荐，零配置）

直接将仓库连接到 Cloudflare Pages，**无需在面板里手填构建命令** —— `wrangler.toml` 已包含：

- `pages_build_output_dir = ".vercel/output/static"`
- `[build] command`：`node scripts/generate-manifest.js && npx @cloudflare/next-on-pages`

Cloudflare 克隆仓库后会自动安装依赖并执行该构建命令，然后把产物发布出去。

**你只需在 Cloudflare 面板设置运行时机密**（构建/运行时都读得到）：

> `Pages → lunatv → Settings → Variables and Secrets`
> 添加以下 **Secret**（加密，不以明文出现在日志）：
>
> - `USERNAME` —— 管理员账号
> - `PASSWORD` —— 管理员密码
> - `UPSTASH_URL` —— Upstash HTTPS Endpoint
> - `UPSTASH_TOKEN` —— Upstash Token

> 也可用命令行：`npx wrangler pages secret put <NAME> --project-name lunatv`

推送代码即自动部署。`NEXT_PUBLIC_*` 构建变量已在 `wrangler.toml` 的构建命令里默认导出
（`STORAGE_TYPE=upstash`、`SITE_NAME=LunaTV`、`SEARCH_MAX_PAGE=5`、`FLUID_SEARCH=true`）。

**自定义站点名 / 豆瓣代理等**：编辑 `wrangler.toml` 里 `[build] command` 的对应 export 后重新推送。

---

## 三、方式 B：本地一键部署（deploy-cloudflare.sh）

1. 克隆本仓库并进入目录。
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
   ```

3. 赋予执行权限并运行：

   ```bash
   chmod +x deploy-cloudflare.sh
   ./deploy-cloudflare.sh
   ```

   脚本会自动：安装 `wrangler` 与 `@cloudflare/next-on-pages` → 生成 manifest → 用 next-on-pages 构建 →
   部署到 Cloudflare Pages 项目 `lunatv` → 设置运行时机密 → 部署代理 Worker `lunatv-proxy`。

   > 未设置 `CLOUDFLARE_API_TOKEN` 时，脚本会引导你执行 `wrangler login`（交互式浏览器登录）。

跳过代理 Worker：`DEPLOY_PROXY_WORKER=false ./deploy-cloudflare.sh`

---

## 四、方式 C：GitHub Actions 自动部署

推送即部署：每次向 `main` 分支 push，都会自动构建并发布到 Cloudflare Pages。

1. 在本仓库的 **Settings → Secrets and variables → Actions** 中配置：
   - **Secrets**：`CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID`、`USERNAME`、`PASSWORD`、`UPSTASH_URL`、`UPSTASH_TOKEN`
   - **Variables**（可选，覆盖构建时内联的默认值）：`NEXT_PUBLIC_SITE_NAME`、`NEXT_PUBLIC_SEARCH_MAX_PAGE`、
     `NEXT_PUBLIC_FLUID_SEARCH`、`SITE_BASE`、`ANNOUNCEMENT`、
     `NEXT_PUBLIC_DOUBAN_PROXY_TYPE`、`NEXT_PUBLIC_DOUBAN_IMAGE_PROXY_TYPE`
2. 推送代码到 `main`，在 **Actions** 标签页查看部署进度。

> ⚠️ 若已启用「方式 A：Git 集成」，再开启本 Actions 会造成**双重部署**（两者都往 `lunatv` 项目发布）。
> 建议二选一：Git 集成开 Actions 就关，或只用 Actions 就把 Git 集成的「自动部署」关掉。

---

## 五、自定义域名

1. Cloudflare 面板 `Pages → lunatv → Custom domains → Set up a custom domain`。
2. 代理 Worker 自定义域名：编辑 `wrangler.proxy.toml` 的 `routes`。

---

## 六、文件说明

| 文件 | 作用 |
| --- | --- |
| `wrangler.toml` | Cloudflare Pages 配置：**含 `[build]` 构建命令**、产物目录、运行时变量、兼容性 |
| `wrangler.proxy.toml` | 代理 Worker（`proxy.worker.js`）的独立配置 |
| `deploy-cloudflare.sh` | 本地一键部署脚本 |
| `.github/workflows/deploy-cloudflare.yml` | 推送即自动部署的 CI 工作流（方式 C） |
| `next.config.js` | 已做兼容：`output: 'standalone'` 仅在非 Cloudflare 构建/运行时启用 |

---

## 七、排错

- **`Output directory ".vercel/output/static" not found`**
  → 说明构建步骤被跳过。确保 `wrangler.toml` 里有 `[build] command`（已包含），且 Cloudflare 是「连接仓库」的 Git 集成模式。
- **构建报 `output: 'standalone' is not compatible`**
  → 确保构建时 `NEXT_ON_PAGES=1` 或 `CF_PAGES` 被设置（构建命令与 CI 已处理；`next.config.js` 同时兼容两种）。
- **页面空白 / 收藏不同步**
  → 确认 `NEXT_PUBLIC_STORAGE_TYPE=upstash` 且 `UPSTASH_URL` / `UPSTASH_TOKEN` 正确。
- **代理 Worker 跨域 / 403**
  → 检查 `wrangler.proxy.toml` 的 `routes`；Worker 默认已开启 CORS。
- **Node 版本相关报错**
  → 在 Cloudflare 面板 `Pages → lunatv → Settings → Build & deployments` 的 Build system / 环境变量里设置 `NODE_VERSION=20`，或确认默认 Node ≥ 18.17。
- **Pages 部署提示 project not found**
  → 首次运行会自动创建项目 `lunatv`；也可在 Cloudflare 面板手动新建同名项目。
