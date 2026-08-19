#!/usr/bin/env bash
# LunaTV · Cloudflare Workers 构建包装脚本（OpenNext）
# 用途：在「构建阶段」导出必要的构建/运行时变量，再执行 OpenNext 构建。
# 在 Cloudflare 面板（Workers Builds / Git 集成）的 Build command 中填：
#   bash scripts/build-cloudflare.sh
#
# ⚠️ 安全提示：UPSTASH_URL / UPSTASH_TOKEN 已写死在下方，会随仓库公开。
#    如怀疑泄露，请到 Upstash 控制台重置 REST token。
set -euo pipefail

export OPEN_NEXT_BUILD=1
export NEXT_PUBLIC_STORAGE_TYPE="${NEXT_PUBLIC_STORAGE_TYPE:-upstash}"
export NEXT_PUBLIC_SITE_NAME="${NEXT_PUBLIC_SITE_NAME:-LunaTV}"
export NEXT_PUBLIC_SEARCH_MAX_PAGE="${NEXT_PUBLIC_SEARCH_MAX_PAGE:-5}"
export NEXT_PUBLIC_FLUID_SEARCH="${NEXT_PUBLIC_FLUID_SEARCH:-true}"
export UPSTASH_URL="${UPSTASH_URL:-https://awaited-lizard-38990.upstash.io}"
export UPSTASH_TOKEN="${UPSTASH_TOKEN:-AZhOAAIgcDFlZDg4NTBmNzE0ODc0NDM1ODVmMmJkOGEwYWE5NTdjMw}"

node scripts/generate-manifest.js && pnpm exec opennextjs-cloudflare build
