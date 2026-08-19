/** @type {import('next').NextConfig} */
/* eslint-disable @typescript-eslint/no-var-requires */
const path = require('path');

// Cloudflare 构建时禁用 standalone：
// - 旧方案 next-on-pages（Pages）不兼容 output:'standalone'；
// - 新方案 OpenNext（Workers）同样不需要 standalone；
// - Docker 部署才需要 standalone（见 Dockerfile）。
// OpenNext 构建时通过 OPEN_NEXT_BUILD=1 标记（deploy 脚本 / CI 设置），
// 此时与 CF_PAGES / NEXT_ON_PAGES 一样禁用 standalone。
const isCloudflareBuild =
  process.env.NEXT_ON_PAGES === '1' ||
  !!process.env.CF_PAGES ||
  process.env.OPEN_NEXT_BUILD === '1';
const nextConfig = {
  ...(isCloudflareBuild ? {} : { output: 'standalone' }),
  eslint: {
    dirs: ['src'],
  },

  reactStrictMode: false,
  swcMinify: false,

  experimental: {
    instrumentationHook: process.env.NODE_ENV === 'production',
  },

  // Uncoment to add domain whitelist
  images: {
    unoptimized: true,
    remotePatterns: [
      {
        protocol: 'https',
        hostname: '**',
      },
      {
        protocol: 'http',
        hostname: '**',
      },
    ],
  },

  webpack(config) {
    // Grab the existing rule that handles SVG imports
    const fileLoaderRule = config.module.rules.find((rule) =>
      rule.test?.test?.('.svg')
    );

    config.module.rules.push(
      // Reapply the existing rule, but only for svg imports ending in ?url
      {
        ...fileLoaderRule,
        test: /\.svg$/i,
        resourceQuery: /url/, // *.svg?url
      },
      // Convert all other *.svg imports to React components
      {
        test: /\.svg$/i,
        issuer: { not: /\.(css|scss|sass)$/ },
        resourceQuery: { not: /url/ }, // exclude if *.svg?url
        loader: '@svgr/webpack',
        options: {
          dimensions: false,
          titleProp: true,
        },
      }
    );

    // Modify the file loader rule to ignore *.svg, since we have it handled now.
    fileLoaderRule.exclude = /\.svg$/i;

    config.resolve.fallback = {
      ...config.resolve.fallback,
      net: false,
      tls: false,
      crypto: false,
    };

    // Cloudflare Worker 运行时不支持 TCP（node:net / node:tls）。
    // 本项目在 CF 上只用 Upstash（HTTP），但 db.ts 仍静态引用了 TCP 版 redis 包。
    // 用占位模块替换它，确保 .next 产物（OpenNext 的 esbuild 步骤会重新打包它）
    // 不含 node:net。仅当 STORAGE_TYPE=redis|kvrocks 时才会真正调用，CF 上不会发生。
    if (isCloudflareBuild) {
      config.resolve.alias = {
        ...(config.resolve.alias || {}),
        redis: path.resolve(__dirname, 'src/lib/redis-stub.js'),
      };
    }

    return config;
  },
};

const withPWA = require('next-pwa')({
  dest: 'public',
  disable: process.env.NODE_ENV === 'development',
  register: true,
  skipWaiting: true,
});

module.exports = withPWA(nextConfig);
