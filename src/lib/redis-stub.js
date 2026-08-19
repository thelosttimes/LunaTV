// Cloudflare (OpenNext Workers) 构建占位模块。
// Worker 运行时不支持 TCP（node:net / node:tls），而 Cloudflare 部署只使用 Upstash（HTTP 客户端）。
// 此 stub 通过 next.config.js 的 webpack alias 替换 TCP 版 `redis` 包，
// 避免把 node:net 打进 .next 产物（OpenNext 的 esbuild 步骤不会再继承 webpack 的 resolve.fallback）。
// 仅 OPEN_NEXT_BUILD / CF 构建时启用；只有 STORAGE_TYPE=redis|kvrocks 才会真正调用，
// 而 Cloudflare 上只使用 upstash，因此永远不会被执行。
function createClient() {
  throw new Error(
    'TCP redis client is unavailable on Cloudflare Workers. Use NEXT_PUBLIC_STORAGE_TYPE=upstash instead.'
  );
}

const RedisClientType = undefined;

export { createClient, RedisClientType };
