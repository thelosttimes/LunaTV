#!/usr/bin/env bash
#
# LunaTV · Cloudflare Workers 一键部署脚本（OpenNext 适配器）
# 将 Next.js 应用部署到 Cloudflare Worker（Node.js 运行时），并可部署代理 Worker。
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

# ---------- 构建时环境变量 ----------
# NEXT_PUBLIC_* 必须在「构建时」导出才会内联进前端包。
# OPEN_NEXT_BUILD=1 让 next.config.js 在 OpenNext 构建时禁用 output:'standalone'（Docker 才需要 standalone）。
# UPSTASH_* 已写死在 wrangler.jsonc [vars]（运行时读取），这里也导出一份以防万一。
export OPEN_NEXT_BUILD=1
export NEXT_PUBLIC_STORAGE_TYPE="${NEXT_PUBLIC_STORAGE_TYPE:-upstash}"
export NEXT_PUBLIC_SITE_NAME="${NEXT_PUBLIC_SITE_NAME:-LunaTV}"
export NEXT_PUBLIC_SEARCH_MAX_PAGE="${NEXT_PUBLIC_SEARCH_MAX_PAGE:-5}"
export NEXT_PUBLIC_FLUID_SEARCH="${NEXT_PUBLIC_FLUID_SEARCH:-true}"
[ -n "${SITE_BASE:-}" ] && export SITE_BASE
[ -n "${ANNOUNCEMENT:-}" ] && export ANNOUNCEMENT
[ -n "${NEXT_PUBLIC_DISABLE_YELLOW_FILTER:-}" ] && export NEXT_PUBLIC_DISABLE_YELLOW_FILTER
[ -n "${NEXT_PUBLIC_DOUBAN_PROXY_TYPE:-}" ] && export NEXT_PUBLIC_DOUBAN_PROXY_TYPE
[ -n "${NEXT_PUBLIC_DOUBAN_IMAGE_PROXY_TYPE:-}" ] && export NEXT_PUBLIC_DOUBAN_IMAGE_PROXY_TYPE
export UPSTASH_URL="${UPSTASH_URL:-https://awaited-lizard-38990.upstash.io}"
export UPSTASH_TOKEN="${UPSTASH_TOKEN:-AZhOAAIgcDFlZDg4NTBmNzE0ODc0NDM1ODVmMmJkOGEwYWE5NTdjMw}"

info "存储类型: ${NEXT_PUBLIC_STORAGE_TYPE}（Cloudflare 仅支持 upstash）"

# ---------- 构建（OpenNext -> Cloudflare Worker） ----------
# opennextjs-cloudflare build 会在内部调用 next build（即 package.json 的 build 脚本：
# pnpm gen:manifest && next build），生成 .open-next/worker.js 与 .open-next/assets。
info "构建 Next.js -> Cloudflare Worker (OpenNext)"
node scripts/generate-manifest.js && pnpm exec opennextjs-cloudflare build
ok "构建完成：.open-next/"

# ---------- 部署 Worker ----------
info "部署到 Cloudflare Worker 项目: ${PROJECT_NAME}"
pnpm exec opennextjs-cloudflare deploy
ok "Worker 部署完成"

# ---------- 设置运行时机密（可选） ----------
# UPSTASH_URL/TOKEN 已写死在 wrangler.jsonc [vars]；以下仅补充管理员凭据（如有）。
set_secret() {
  local name="$1"; local val="${2:-}"
  if [ -z "$val" ]; then
    warn "未提供 $name，跳过（如需管理员登录请到 Cloudflare 面板或执行 wrangler secret put $name）"
    return
  fi
  info "设置 Worker 机密: $name"
  printf '%s' "$val" | $WRANGLER_CMD secret put "$name" >/dev/null 2>&1 \
    && ok "$name 已设置" || warn "$name 设置失败，请到 Cloudflare 面板手动设置"
}
set_secret USERNAME "${USERNAME:-}"
set_secret PASSWORD "${PASSWORD:-}"

# ---------- 部署代理 Worker（可选） ----------
if [ "${DEPLOY_PROXY_WORKER}" = "true" ]; then
  info "部署代理 Worker: ${PROXY_NAME}"
  $WRANGLER_CMD deploy --config wrangler.proxy.toml
  ok "代理 Worker 部署完成"
else
  info "跳过代理 Worker 部署（DEPLOY_PROXY_WORKER != true）"
fi

ok "🎉 全部完成！访问你的 Cloudflare Worker 域名查看站点。"
