# syntax=docker/dockerfile:1
FROM node:22-bookworm-slim

ARG DSH_VERSION=next
ENV NODE_ENV=production
# 低内存服务器护栏: 限制 V8 堆 (构建期 npm 与运行期 dsh 都生效)
ENV NODE_OPTIONS=--max-old-space-size=768

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates tini curl \
 && rm -rf /var/lib/apt/lists/*

# node 镜像自带 UID 1000 的 node 用户, 直接复用 (useradd -u 1000 会因 UID 冲突失败)
RUN mkdir -p /data/dsh-home /data/workspace \
 && chown -R node:node /data

RUN npm install -g "@deepseek-ai/dsh@${DSH_VERSION}" && dsh --version

# dsh plugin 只是把参数转发给 PATH 上的 pnpm, 没有 pnpm 插件预装与 link 安装都会失败
# (官方运行时内置的是 pnpm 11, 这里对齐大版本, 避免 lockfile 格式不兼容)
RUN npm install -g pnpm@11 && pnpm --version

COPY --chown=dsh:dsh bootstrap/ /opt/bootstrap/
COPY --chown=dsh:dsh entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/bootstrap/*.sh /opt/entrypoint.sh

USER node
WORKDIR /data/workspace
ENV DSH_HOME=/data/dsh-home
VOLUME ["/data/dsh-home", "/data/workspace"]
EXPOSE 3080

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/entrypoint.sh"]
