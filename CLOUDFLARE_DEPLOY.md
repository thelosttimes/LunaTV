# LunaTV · Cloudflare Pages 部署指南

将 **LunaTV（MoonTV）** 部署到 [Cloudflare Pages](https://pages.cloudflare.com/)，
使用 [@cloudflare/next-on-pages](https://github.com/cloudflare/next-on-pages) 把 Next.js 应用跑在 Cloudflare 边缘网络，
并配套部署独立的代理 Worker（`proxy.worker.js`）。

> 部署思路参考 [LibreTV](https://github.com/thelosttimes/LibreTV) 的 Cloudflare Pages 方式。

---

## ⚠️ 关键约束（必读）

1. **Cloudflare Pages 的 `wrangler.toml` 不支持 `[build]` 命令。**
   该 key 只对 Workers 有效，Pages 读取它会直接报错：
   `Configuration file for Pages projects does not support "build"`。
   **构建命令必须在以下两者之一指定（二选一，不能写在 wrangler.toml）**：
   - GitHub Actions 工作流（推荐，已在代码里定义）；或
   - Cloudflare 面板的「Build & deployments」设置。
2. **存储只能用 Upstash。** Cloudflare 运行时不支持 TCP，`redis` / `kvrocks` 无法使用。
   必须 `NEXT_PUBLIC_STORAGE_TYPE=upstash` + `UPSTASH_URL` + `UPSTASH_TOKEN`。
3. **`NEXT_PUBLIC_*` 必须在「构建时」导出**才会被内联进前端包（CI / 面板 Build 变量）。
4. **不要同时启用「Git 集成自动部署」和「GitHub Actions」**，二者都会往 `lunatv` 发布，会双重部署/冲突。
5. **定时任务（cron）** `/api/cron`（原 `vercel.json` 的 `0 1 * * *`）在 Pages 上不会自动触发，请用外部定时任务调用你的 `/api/cron` 接口。

---

## 准备

1. 注册 [Cloudflare](https://dash.cloudflare.com/) 账号，获取：
   - **Account ID**：右下角「账户 ID」
   - **API Token**：`My Profile → API Tokens → Create Token`，权限需包含
     `Account > Cloudflare Pages > Edit` 以及 `Account > Workers Scripts > Edit`。
2. 注册 [Upstash](https://upstash.com/) 并新建一个 Redis 数据库，复制：
   - **HTTPS Endpoint**（`UPSTASH_URL`，形如 `https://xxx.upstash.io`）
   - **Token**（`UPSTASH_TOKEN`）

---

## 方式一（推荐）：GitHub Actions 直接上传

构建在 GitHub 的 CI 里完成，再用 `wrangler pages deploy` 直接上传产物。
**不依赖 Cloudflare 面板里的构建命令**，全部在代码里定义。

### 步骤
1. **关闭 Cloudflare 的 Git 集成自动部署**（否则它仍会在 push 时克隆并尝试构建而报错）：
   > Cloudflare 面板 → `Pages → lunatv → Settings → Build & deployments` → 关闭 "Automatic deployments"（或断开 Git 连接 / 删除该项目）。
   > 推荐：直接**删除 `lunatv` 项目**，让 Actions 第一次运行时用 `wrangler pages deploy --project-name lunatv` 自动重建为「直接上传」项目，避免 Git 连接冲突。
2. 在仓库 **Settings → Secrets and variables → Actions** 配置：
   - **Secrets**：`CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID`、`USERNAME`、`PASSWORD`、`UPSTASH_URL`、`UPSTASH_TOKEN`
   - **Variables**（可选，覆盖构建时默认值）：`NEXT_PUBLIC_SITE_NAME`、`NEXT_PUBLIC_SEARCH_MAX_PAGE`、`NEXT_PUBLIC_FLUID_SEARCH`、`SITE_BASE`、`ANNOUNCEMENT`、`NEXT_PUBLIC_DOUBAN_PROXY_TYPE`、`NEXT_PUBLIC_DOUBAN_IMAGE_PROXY_TYPE`
3. 推送（或手动触发 Actions）→ 工作流自动 `generate-manifest` + `next-on-pages` 构建 → 上传到 Pages → 写入运行时机密 → 部署代理 Worker。

> 工作流文件：`.github/workflows/deploy-cloudflare.yml`

---

## 方式二：Cloudflare 原生 Git 集成

构建由 Cloudflare 自己的构建器执行（不是 Actions）。需要在面板里配置构建命令与环境变量。

### 步骤
1. Cloudflare 面板 → `Pages → 创建项目 → 连接 Git 仓库 → 选择 LunaTV`。
2. **Build & deployments** 设置：
   - **Build command**：`node scripts/generate-manifest.js && npx @cloudflare/next-on-pages`
   - **Output directory / Build output directory**：`.vercel/output/static`
   - **Build environment variables**（作用域选 Build，确保内联到前端）：
     - `NEXT_PUBLIC_STORAGE_TYPE` = `upstash`
     - `NEXT_PUBLIC_SITE_NAME` = `LunaTV`
     - `NEXT_PUBLIC_SEARCH_MAX_PAGE` = `5`
     - `NEXT_PUBLIC_FLUID_SEARCH` = `true`
     - （可选）`NEXT_PUBLIC_DOUBAN_PROXY_TYPE`、`NEXT_PUBLIC_DOUBAN_IMAGE_PROXY_TYPE` 等
   - Node 版本：在 **Build system** 或环境变量设 `NODE_VERSION=20`（若默认低于 18.17）。
3. **Variables and Secrets** 添加运行时机密（Secret）：`USERNAME`、`PASSWORD`、`UPSTASH_URL`、`UPSTASH_TOKEN`。
4. 推送即部署。

> ⚠️ 此方式下请**禁用** `.github/workflows/deploy-cloudflare.yml`（在 Actions 页面 Disable workflow），避免双重部署。

---

## 自定义域名

- Pages 自定义域名：`Pages → lunatv → Custom domains`。
- 代理 Worker 自定义域名：编辑 `wrangler.proxy.toml` 的 `routes`。

---

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `wrangler.toml` | Pages 配置：`pages_build_output_dir`、运行时 `[vars]`、兼容性。**不含 `[build]`（Pages 不支持）** |
| `wrangler.proxy.toml` | 代理 Worker（`proxy.worker.js`）独立配置（`lunatv-proxy`） |
| `deploy-cloudflare.sh` | 本地一键部署脚本（直接上传方式） |
| `.github/workflows/deploy-cloudflare.yml` | 推送即自动构建并直接上传（方式一） |
| `next.config.js` | 兼容：Cloudflare 构建/运行时禁用 `output:'standalone'` |

---

## 排错

- **`Configuration file for Pages projects does not support "build"`**
  → `wrangler.toml` 里有 `[build]`，Pages 不支持。已移除；构建命令改到 Actions / 面板。
- **`Output directory ".vercel/output/static" not found`**
  → 构建没跑。确认走方式一（Actions）或方式二（面板已设 Build command + Output dir）。
- **`This Pages project is connected to a git repository...`**
  → Git 集成项目不能直接上传。删除该项目后由 Actions 重建，或改用方式二。
- **`output: 'standalone' is not compatible`**
  → 构建时未设置 `NEXT_ON_PAGES=1` / `CF_PAGES`；Actions 与面板 Build 变量已处理。
- **页面空白 / 收藏不同步**
  → 确认 `NEXT_PUBLIC_STORAGE_TYPE=upstash` 且 `UPSTASH_URL` / `UPSTASH_TOKEN` 正确。
- **代理 Worker 跨域 / 403**
  → 检查 `wrangler.proxy.toml` 的 `routes`；Worker 默认已开启 CORS。
