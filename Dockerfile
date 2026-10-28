# syntax=docker/dockerfile:1
#
# 一个镜像仓, 两档构建:
#   --target slim    只有 dsh 本体 + 启动脚本          -> :slim   (mini / chat / coder)
#   --target capable + Python/LibreOffice/中文字体     -> :latest (full / harness)
#
# 为什么必须分档: PPT/文档/PDF 这些能力靠的是系统依赖(office 技能会去找
# Python 库和 LibreOffice), 装插件装不出来。把 LibreOffice 塞进所有档位
# 又会让只想聊天的人白扛 1G+。
ARG DSH_VERSION=next

# ============================================================================
# base: 所有档位共用的底座
# ============================================================================
FROM node:22-bookworm-slim AS base
ARG DSH_VERSION
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

ENV DSH_HOME=/data/dsh-home
WORKDIR /data/workspace

# 安装方案 + 启动脚本: 两档共用, 差别只在系统依赖
COPY --chown=node:node plans/ /opt/plans/
COPY --chown=node:node scripts/ /opt/scripts/
COPY --chown=node:node bootstrap/ /opt/bootstrap/
COPY --chown=node:node entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/bootstrap/*.sh /opt/scripts/*.sh /opt/entrypoint.sh 2>/dev/null || true

USER node
VOLUME ["/data/dsh-home", "/data/workspace"]
EXPOSE 3080
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/entrypoint.sh"]

# ============================================================================
# slim: 只有 dsh 本体 (mini / chat / coder)
# ============================================================================
FROM base AS slim

# ============================================================================
# capable: 能"出东西"的一档 (full / harness)
# ============================================================================
FROM base AS capable
USER root

# 预留位: 默认不装, 需要时 --build-arg 打开
#   INSTALL_FFMPEG=1    视频合成/抽帧
#   INSTALL_CHROMIUM=1  需要真实浏览器的抓取/自动化
ARG INSTALL_FFMPEG=0
ARG INSTALL_CHROMIUM=0

# Office 文档(Word/Excel/PPT)与 PDF 导出:
#   python 库负责"写", LibreOffice 负责"渲染/转换", CJK 字体负责中文不乱码。
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 python3-pip \
      libreoffice-writer libreoffice-impress libreoffice-calc \
      fonts-noto-cjk \
 && rm -rf /var/lib/apt/lists/*

# 与 dsh 的 office-* 技能对齐 (见 office-pptx / office-xlsx / office-docx 的 SKILL.md)
RUN pip3 install --break-system-packages --no-cache-dir \
      python-docx python-pptx openpyxl XlsxWriter Pillow lxml

RUN set -eux; \
    if [ "${INSTALL_FFMPEG}" = "1" ]; then \
      apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*; \
    fi; \
    if [ "${INSTALL_CHROMIUM}" = "1" ]; then \
      apt-get update && apt-get install -y --no-install-recommends chromium && rm -rf /var/lib/apt/lists/*; \
    fi

USER node
