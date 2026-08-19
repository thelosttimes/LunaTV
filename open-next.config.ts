import { defineCloudflareConfig } from "@opennextjs/cloudflare";

// LunaTV（MoonTV）迁移到 Cloudflare Workers（OpenNext 适配器）。
// 使用 Node.js 运行时（nodejs_compat），无需逐路由声明 runtime='edge'，
// 因此保留原有的 crypto.scryptSync 密码哈希与 @upstash/redis HTTP 客户端即可。
export default defineCloudflareConfig({});
