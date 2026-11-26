# syntax=docker/dockerfile:1
#
# 一个镜像仓, 两档环境:
#   --target slim    只有 dsh 本体 + 启动脚本          -> :slim   (chat)
#   --target capable + Python/LibreOffice/中文字体     -> :latest (full / harness / dev)
#
# 为什么必须分档: PPT/文档/PDF 这些能力靠的是系统依赖(office 技能会去找
# Python 库和 LibreOffice), 装插件装不出来。把 LibreOffice 塞进所有档位
# 又会让只想聊天的人白扛 1G+。
#
# 方向(plans/)的日常来源是挂载: compose 挂 ./plans:/opt/plans:ro, 改清单不用重建。
# 镜像里另外内嵌一份默认值到 /opt/plans-default(见 scripts/bake-plans.sh):
# 云原生开发这类没有 compose、也挂不了宿主目录的环境, 靠它才起得来。
ARG DSH_VERSION=next

# ============================================================================
# base: 所有档位共用的底座
# ============================================================================
# node 24: @deepseek-ai/dsh 0.2.2+ 的 engines 要求 node >=24.9.0
# (镜像 tag 跟 24 大版本走, 只要 >=24.9.0 就行; 别改回 22)
FROM node:24-bookworm-slim AS base
ARG DSH_VERSION
ENV NODE_ENV=production
# 低内存服务器护栏: 限制 V8 堆 (构建期 npm 与运行期 dsh 都生效)
ENV NODE_OPTIONS=--max-old-space-size=768

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates tini \
 && rm -rf /var/lib/apt/lists/*

# node 镜像自带 UID 1000 的 node 用户, 直接复用 (useradd -u 1000 会因 UID 冲突失败)
RUN mkdir -p /data/dsh-home /data/workspace \
 && chown -R node:node /data

# dsh 把插件管理委托给 pnpm, slim/full/dev 首启要装插件, 所以 pnpm 必须可用。
# 保留全局安装: `dsh plugin` 直接执行 PATH 上的 pnpm, 这里对齐官方运行时大版本。
RUN npm install -g "@deepseek-ai/dsh@${DSH_VERSION}" pnpm@11 \
 && dsh --version && pnpm --version && npm cache clean --force

ENV DSH_HOME=/data/dsh-home
WORKDIR /data/workspace

# 启动逻辑 + 镜像内初始化: 两档共用, 差别只在系统依赖。
COPY --chown=node:node scripts/plan-boot.sh /opt/scripts/plan-boot.sh
COPY --chown=node:node bootstrap/ /opt/bootstrap/
COPY --chown=node:node entrypoint.sh /opt/entrypoint.sh
# 方向数据的内嵌默认值: 兜底没有挂载的环境(云原生开发没有 compose, 挂不了宿主目录)。
# 注意 .dockerignore 排了 plans/, 构建上下文里没有它 —— 脚本改从 .git 读 HEAD 的
# plans/, 读不到就跳过(挂载方式不受影响)。
COPY --chown=node:node scripts/bake-plans.sh /tmp/bake-plans.sh
RUN chmod +x /opt/bootstrap/*.sh /opt/scripts/*.sh /opt/entrypoint.sh /tmp/bake-plans.sh 2>/dev/null || true \
 && sh /tmp/bake-plans.sh /opt/plans-default \
 && rm -f /tmp/bake-plans.sh

USER node
VOLUME ["/data/dsh-home", "/data/workspace"]
EXPOSE 3080
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/entrypoint.sh"]

# ============================================================================
# slim: base 环境, 只有 dsh 本体 (chat)
# ============================================================================
FROM base AS slim

# ============================================================================
# ci: headless 专用档 (预置 profile, 容器启动零 dsh plugin add)
# ----------------------------------------------------------------------------
# CI 每次冷启都装插件太慢, 这一档在 build 期就把 headless profile 和实测唯一
# 有用的 agent-teams 装好, 存到 /opt/ci-profile (非 VOLUME)。
# 不能写 /data/dsh-home: 那是 VOLUME, 构建期写入在运行时会被空卷盖掉。
# plan-boot 启动 ci 方向时从 /opt/ci-profile 本地拷进 DSH_HOME (毫秒级 IO)。
# ============================================================================
FROM base AS ci
USER root

# 构建期用 base 已装好的 pnpm 预置 profile; 保留 pnpm 供用户后续 dsh plugin add。
# 只清理全局 npm 包树里的开发和 sourcemap 文件: ci 运行时只用转译后的 js/cjs,
# 不碰插件目录、dsh 配置和 PATH 上的 pnpm, 也不改变 slim/capable。
RUN mkdir -p /opt/ci-home /opt/ci-profile \
 && DSH_HOME=/opt/ci-home dsh --profile headless --dump-config >/dev/null \
 && DSH_HOME=/opt/ci-home dsh plugin --profile headless add "@chenxu233/dsh-agent-teams@0.2.4" \
 && find "$(npm root -g)" -type f \
      \( -name '*.map' \
         -o \( -name '*.ts' -o -name '*.cts' -o -name '*.mts' -o -name '*.tsx' \) ! -name '*.d.ts' \
      \) -delete \
 && rm -rf /opt/ci-home /root/.npm /root/.cache/pnpm \
 && chown -R node:node /opt/ci-profile
USER node

# ============================================================================
# capable: 能"出东西"的一档 (full / harness / dev)
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
