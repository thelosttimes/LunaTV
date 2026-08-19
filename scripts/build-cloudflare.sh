#!/usr/bin/env bash
# LunaTV · Cloudflare Pages 构建包装脚本
# 用途：在「构建阶段」导出 Upstash 凭据（next build 需要），再执行标准构建。
# 在 Cloudflare 面板 Git 集成的 Build command 中填：bash scripts/build-cloudflare.sh
#
# ⚠️ 安全提示：UPSTASH_URL / UPSTASH_TOKEN 已写死在下方，会随仓库公开。
#    如怀疑泄露，请到 Upstash 控制台重置 REST token。
set -euo pipefail

export UPSTASH_URL="https://awaited-lizard-38990.upstash.io"
export UPSTASH_TOKEN="AZhOAAIgcDFlZDg4NTBmNzE0ODc0NDM1ODVmMmJkOGEwYWE5NTdjMw"

node scripts/generate-manifest.js && pnpm dlx @cloudflare/next-on-pages
