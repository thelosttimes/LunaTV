# LunaTV · Cloudflare Workers 部署指南（OpenNext）

将 **LunaTV（MoonTV）** 部署到 [Cloudflare Workers](https://workers.cloudflare.com/)，
使用 [@opennextjs/cloudflare](https://github.com/opennextjs/opennextjs-cloudflare)（OpenNext 适配器）
把 Next.js 14（App Router）跑在 Cloudflare 的 **Node.js 运行时（nodejs_compat）** 上。

> 这是原 “Cloudflare Pages + next-on-pages” 方案的替代方案。next-on-pages 要求所有非静态路由声明 `runtime='edge'`，
> 而 LunaTV 依赖 Node 独占 API（`crypto.scryptSync` 密码哈希、`@upstash/redis` HTTP 客户端等），无法改为 Edge。
> OpenNext 使用 Node 运行时，**无需改动任何路由代码**。

## ✅ 为什么用 OpenNext + Workers

| 方案 | 运行时 | 是否需要改路由 | 结果 |
| --- | --- | --- | --- |
| `@cloudflare/next-on-pages` (Pages) | Edge | 需要（41 条路由加 `runtime='edge'`） | ❌ 构建失败 |
| `@opennextjs/cloudflare` (Workers) | Node.js (`nodejs_compat`) | 不需要 | ✅ 可直接构建 |

## ⚠️ 关键约束（必读）

1. **存储只能用 Upstash。** Cloudflare 运行时不支持 TCP，`redis` / `kvrocks` 无法使用。
   必须 `NEXT_PUBLIC_STORAGE_TYPE=upstash` + `UPSTASH_URL` + `UPSTASH_TOKEN`。
   LunaTV 的 `upstash.db.ts` 使用 `@upstash/redis`（HTTP 客户端），在 Workers 上可正常工作。
2. **`NEXT_PUBLIC_*` 必须在「构建时」导出**才会内联进前端包（CI 构建步骤 / 面板 Build 变量）。
3. **删除/禁用旧的 Pages 项目**，避免与新的 Worker 冲突（见下方「迁移自 Pages」）。
4. **代理 Worker（`proxy.worker.js`）** 仍独立部署（见 `wrangler.proxy.toml`），与本次迁移无关。

## 准备

1. 注册 [Cloudflare](https://dash.cloudflare.com/) 账号，获取：
   - **Account ID**：右下角「账户 ID」
   - **API Token**：`My Profile → API Tokens → Create Token`，权限需包含
     `Account > Workers Scripts > Edit`（部署 Worker 用）。
2. 注册 [Upstash](https://upstash.com/) 并新建一个 Redis 数据库，复制：
   - **HTTPS Endpoint**（`UPSTASH_URL`，形如 `https://xxx.upstash.io`）
   - **Token**（`UPSTASH_TOKEN`）
   - 这两个值已**写死**在 `wrangler.jsonc` 的 `[vars]` 中（公开仓库可见；如泄露请在 Upstash 重置）。

## 新增/修改的文件

| 文件 | 作用 |
| --- | --- |
| `wrangler.jsonc` | **Workers 配置**：`main: .open-next/worker.js`、assets 绑定、`nodejs_compat` 兼容标志、`WORKER_SELF_REFERENCE` 服务绑定、运行时 `[vars]`（含写死的 Upstash） |
| `open-next.config.ts` | OpenNext Cloudflare 适配器配置（默认 Node 运行时） |
| `.dev.vars` | 本地开发环境变量（`NEXTJS_ENV=development`） |
| `public/_headers` | 静态资源长缓存头 |
| `package.json` | 新增 `@opennextjs/cloudflare@1.13.0`、`wrangler` 开发依赖；新增 `cf:build` / `cf:deploy` / `cf:preview` 脚本 |
| `next.config.js` | OpenNext 构建时（`OPEN_NEXT_BUILD=1`）同样禁用 `output:'standalone'`（Docker 才需要 standalone） |
| `.gitignore` | 忽略 `.open-next` 构建产物 |
| `deploy-cloudflare.sh` | 本地一键部署（OpenNext → Worker） |
| `.github/workflows/deploy-cloudflare.yml` | 推送即自动构建并部署到 Worker（推荐方式） |
| `scripts/build-cloudflare.sh` | Cloudflare Workers Builds / 手动构建包装脚本 |
| `wrangler.pages.toml` | 旧 Pages 配置（已废弃，仅作历史参考，不再使用） |
| `wrangler.toml` | **已删除**（避免与 `wrangler.jsonc` 冲突；wrangler 只会自动读取 `wrangler.*` 之一） |

## 方式一（推荐）：GitHub Actions 自动部署

推送（`push` 到 `main`）即触发 `.github/workflows/deploy-cloudflare.yml`：
`pnpm install` → `opennextjs-cloudflare build`（内部调用 `next build`）→ `opennextjs-cloudflare deploy` → 部署代理 Worker。

### 步骤
1. 在仓库 **Settings → Secrets and variables → Actions** 配置：
   - **Secrets**：`CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID`（部署 Worker 用，需 `Workers Scripts:Edit` 权限）。
     `USERNAME`、`PASSWORD` 可选（管理员登录凭据，也可稍后在 Cloudflare 面板 `wrangler secret put`）。
     `UPSTASH_URL` / `UPSTASH_TOKEN` 可选——已写死在 `wrangler.jsonc`，不强制需要。
   - **Variables**（可选，覆盖构建时默认值）：`NEXT_PUBLIC_SITE_NAME`、`NEXT_PUBLIC_SEARCH_MAX_PAGE`、`NEXT_PUBLIC_FLUID_SEARCH`、`SITE_BASE`、`ANNOUNCEMENT`、`NEXT_PUBLIC_DOUBAN_PROXY_TYPE`、`NEXT_PUBLIC_DOUBAN_IMAGE_PROXY_TYPE`、`DEPLOY_PROXY_WORKER`。
2. **删除或断开旧的 Pages 项目**（见下方「迁移自 Pages」），避免双重部署。
3. 推送代码 → Actions 自动完成部署。Worker 域名形如 `https://lunatv.<subdomain>.workers.dev`。

## 方式二：本地一键脚本

```bash
# 交互式（无令牌时引导 wrangler login）
./deploy-cloudflare.sh

# 非交互 / CI
CLOUDFLARE_API_TOKEN=xxx CLOUDFLARE_ACCOUNT_ID=yyy ./deploy-cloudflare.sh

# 跳过代理 Worker
DEPLOY_PROXY_WORKER=false ./deploy-cloudflare.sh
```

也可直接用 pnpm 脚本：
```bash
pnpm cf:build     # 仅构建（生成 .open-next/）
pnpm cf:preview   # 本地 Worker 运行时预览
pnpm cf:deploy    # 构建并部署到 Cloudflare Worker
```

## 方式三：Cloudflare Workers Builds（Git 集成）

若使用 Cloudflare 面板自带的 Workers Builds：
- Build command：`bash scripts/build-cloudflare.sh`
- Deploy command：留空或 `npx opennextjs-cloudflare deploy`（需配置 `CLOUDFLARE_API_TOKEN`）
- 或直接用方式一的 Actions（推荐）。

## 迁移自 Pages（next-on-pages）

若你之前用旧方案部署过 Pages 项目 `lunatv`：
1. 登录 Cloudflare 面板 → `Workers & Pages` → 找到 `lunatv` Pages 项目 → **Delete**（或断开 Git）。
   - 不删除会导致旧的 Git 集成仍在 push 时尝试用 `next-on-pages` 构建而失败。
2. 新的 Worker 名为 `lunatv`（资源类型不同，与已删除的 Pages 项目不冲突）。
3. 旧 `wrangler.toml` 已删除，配置迁移到 `wrangler.jsonc`；历史可查 `wrangler.pages.toml`。

## 自定义域名

- Worker 自定义域名：`Workers & Pages → lunatv → Settings → Domains`。
- 代理 Worker 自定义域名：编辑 `wrangler.proxy.toml` 的 `routes`。

## 排错

- **`Configuration file ... does not support "build"`** → 旧 Pages 报错，已废弃；新方案用 `wrangler.jsonc` + OpenNext，构建在 CI/脚本里完成。
- **构建报 `UPSTASH_URL and UPSTASH_TOKEN env variables must be set`** → 检查 `NEXT_PUBLIC_STORAGE_TYPE=upstash` 是否导出；OpenNext 构建（`opennextjs-cloudflare build`）内部会调用 `next build`。若仍报，确认 `db.ts` 的懒加载已生效（默认已配置）。
- **部署报权限错误** → 确认 `CLOUDFLARE_API_TOKEN` 拥有 `Workers Scripts:Edit`。
- **页面空白 / 收藏不同步** → 确认 `UPSTASH_URL` / `UPSTASH_TOKEN` 正确（`wrangler.jsonc` [vars] 或 Worker 环境变量）。
- **代理 Worker 跨域 / 403** → 检查 `wrangler.proxy.toml` 的 `routes`；Worker 默认已开启 CORS。
