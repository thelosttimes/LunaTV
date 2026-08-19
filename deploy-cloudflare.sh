#!/usr/bin/env bash
#
# LunaTV · Cloudflare 一键部署脚本
# 将 Next.js 应用部署到 Cloudflare Pages（next-on-pages），并可选部署代理 Worker。
# 文档：./CLOUDFLARE_DEPLOY.md
#
# 用法：
#   ./deploy-cloudflare.sh                                              # 交互式（缺少令牌时引导 wrangler login）
#   CLOUDFLARE_API_TOKEN=xxx CLOUDFLARE_ACCOUNT_ID=yyy ./deploy-cloudflare.sh   # 非交互 / CI
#   DEPLOY_PROXY_WORKER=false ./deploy-cloudflare.sh                    # 跳过代理 Worker
#
set -euo pipefail

# ---------- 颜色 ----------
if [ -t 1 ]; then
  C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_CYAN='\033[0;36m'; C_RESET='\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_RESET=''
fi
info()  { echo -e "${C_CYAN}[INFO]${C_RESET} $*"; }
ok()    { echo -e "${C_GREEN}[OK]${C_RESET} $*"; }
warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
error() { echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2; }

PROJECT_NAME="lunatv"
PROXY_NAME="lunatv-proxy"
DEPLOY_PROXY_WORKER="${DEPLOY_PROXY_WORKER:-true}"
WRANGLER_CMD="npx wrangler"

# ---------- 加载本地环境变量（可选） ----------
if [ -f .env.cloudflare ]; then
  info "加载 .env.cloudflare"
  set -a
  # shellcheck disable=SC1091
  source .env.cloudflare
  set +a
fi

# ---------- 检查 Node ----------
if ! command -v node >/dev/null 2>&1; then
  error "未检测到 Node.js，请先安装 Node.js >= 20 (https://nodejs.org)"
  exit 1
fi
NODE_VER=$(node -v | sed 's/^v//;s/\..*//')
if [ "$NODE_VER" -lt 20 ]; then
  error "Node.js 版本过低（当前 $(node -v)），需要 >= 20"
  exit 1
fi
ok "Node.js $(node -v)"

# ---------- 启用 pnpm ----------
if ! command -v pnpm >/dev/null 2>&1; then
  info "未检测到 pnpm，尝试通过 corepack 启用"
  corepack enable || { error "corepack 启用失败，请手动安装 pnpm"; exit 1; }
fi
ok "pnpm $(pnpm -v 2>/dev/null || echo 'via corepack')"

# ---------- 检查 / 安装 wrangler（便于本地交互使用，CI 中也会自动安装） ----------
if ! command -v wrangler >/dev/null 2>&1; then
  info "本地未找到 wrangler，尝试 npm i -g wrangler"
  npm i -g wrangler >/dev/null 2>&1 || warn "全局安装 wrangler 失败，将改用 npx（需联网）"
fi

# ---------- Cloudflare 认证 ----------
if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  warn "未设置 CLOUDFLARE_API_TOKEN，尝试 wrangler login（交互式浏览器登录）"
  $WRANGLER_CMD login
else
  export CLOUDFLARE_API_TOKEN
  export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:?请在环境变量或 .env.cloudflare 中设置 CLOUDFLARE_ACCOUNT_ID}"
  ok "已使用 CLOUDFLARE_API_TOKEN 认证"
fi

# ---------- 安装项目依赖 ----------
info "安装项目依赖 (pnpm install)"
pnpm install

# ---------- 安装 Cloudflare 构建工具（本地，不修改提交到仓库的 package.json） ----------
info "安装 @cloudflare/next-on-pages"
pnpm add -D wrangler @cloudflare/next-on-pages >/dev/null 2>&1 || warn "pnpm add 失败，将改用 npx 直接调用"

# ---------- 构建时环境变量（NEXT_PUBLIC_* 必须在此导出才会内联进前端） ----------
export NEXT_ON_PAGES=1
export NEXT_PUBLIC_STORAGE_TYPE="${NEXT_PUBLIC_STORAGE_TYPE:-upstash}"
export NEXT_PUBLIC_SITE_NAME="${NEXT_PUBLIC_SITE_NAME:-LunaTV}"
export NEXT_PUBLIC_SEARCH_MAX_PAGE="${NEXT_PUBLIC_SEARCH_MAX_PAGE:-5}"
export NEXT_PUBLIC_FLUID_SEARCH="${NEXT_PUBLIC_FLUID_SEARCH:-true}"
[ -n "${SITE_BASE:-}" ] && export SITE_BASE
[ -n "${ANNOUNCEMENT:-}" ] && export ANNOUNCEMENT
[ -n "${NEXT_PUBLIC_DISABLE_YELLOW_FILTER:-}" ] && export NEXT_PUBLIC_DISABLE_YELLOW_FILTER
[ -n "${NEXT_PUBLIC_DOUBAN_PROXY_TYPE:-}" ] && export NEXT_PUBLIC_DOUBAN_PROXY_TYPE
[ -n "${NEXT_PUBLIC_DOUBAN_IMAGE_PROXY_TYPE:-}" ] && export NEXT_PUBLIC_DOUBAN_IMAGE_PROXY_TYPE

# Upstash 凭据：Cloudflare 运行时不支持 TCP，必须用 Upstash；
# 且 next build 在「构建阶段」就会读取 UPSTASH_URL/UPSTASH_TOKEN（见 src/lib/upstash.db.ts），
# 因此必须在构建前导出，不能只留到部署后设为运行时 Secret。
if [ "${NEXT_PUBLIC_STORAGE_TYPE}" = "upstash" ]; then
  if [ -z "${UPSTASH_URL:-}" ] || [ -z "${UPSTASH_TOKEN:-}" ]; then
    error "存储类型为 upstash，但缺少 UPSTASH_URL / UPSTASH_TOKEN 环境变量。"
    error "请在环境变量或 .env.cloudflare 中设置后再运行本脚本（部署后在运行时也会用到这两个值）。"
    exit 1
  fi
  export UPSTASH_URL
  export UPSTASH_TOKEN
fi

info "存储类型: ${NEXT_PUBLIC_STORAGE_TYPE}（Cloudflare 仅支持 upstash）"

# ---------- 构建 ----------
info "构建 Next.js -> Cloudflare Pages (next-on-pages)"
npx @cloudflare/next-on-pages
ok "构建完成：.vercel/output/static"

# ---------- 部署 Pages ----------
info "部署到 Cloudflare Pages 项目: ${PROJECT_NAME}"
$WRANGLER_CMD pages deploy .vercel/output/static --project-name "$PROJECT_NAME" --commit-dirty=true
ok "Pages 部署完成"

# ---------- 设置运行时机密 ----------
set_secret() {
  local name="$1"; local val="${2:-}"
  if [ -z "$val" ]; then
    warn "未提供 $name，跳过（应用运行时可能报错）。可到 Cloudflare 面板手动设置。"
    return
  fi
  info "设置 Pages 机密: $name"
  printf '%s' "$val" | $WRANGLER_CMD pages secret put "$name" --project-name "$PROJECT_NAME" >/dev/null 2>&1 \
    && ok "$name 已设置" || warn "$name 设置失败，请到 Cloudflare 面板手动设置"
}
set_secret USERNAME "${USERNAME:-}"
set_secret PASSWORD "${PASSWORD:-}"
set_secret UPSTASH_URL "${UPSTASH_URL:-}"
set_secret UPSTASH_TOKEN "${UPSTASH_TOKEN:-}"

# ---------- 部署代理 Worker（可选） ----------
if [ "${DEPLOY_PROXY_WORKER}" = "true" ]; then
  info "部署代理 Worker: ${PROXY_NAME}"
  $WRANGLER_CMD deploy --config wrangler.proxy.toml
  ok "代理 Worker 部署完成"
else
  info "跳过代理 Worker 部署（DEPLOY_PROXY_WORKER != true）"
fi

ok "🎉 全部完成！访问你的 Cloudflare Pages 域名查看站点。"
