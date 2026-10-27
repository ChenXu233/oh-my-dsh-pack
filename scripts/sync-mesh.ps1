#Requires -Version 5.1
<#
.SYNOPSIS
  dsh-workspace-mesh 开发迭代: 本地构建 -> 同步到远端 -> 重启远端 dsh。

.DESCRIPTION
  免发布迭代链路 (只适用于插件作者本人的开发环境, 详见 AGENT.md):
    1. 本地 pnpm build, 产出 lib/
    2. 把 lib/ + package.json + cordis.patch.yml 同步到远端的源码目录
    3. 远端以 docker-compose.dev.yml 覆盖层启动并重启容器, bootstrap-dev 里的
       脚本用 link: 规格把插件装进 web profile (落在 dsh-home 卷里, 不丢)

  远端主机不在仓库里出现: 用 SSH config 里的别名 (默认 dsh-server, 指"跑 dsh 的那台机器",
  与具体插件无关), 或设置环境变量 DSH_SSH_HOST。仓库里不写 IP、域名、凭据。

.PARAMETER SshHost
  SSH 别名。不写主机地址, 因为别名到地址的映射放在本机 ~/.ssh/config。

.PARAMETER LocalRepo
  本地插件仓库路径, 默认取本仓库同级的 dsh-workspace-mesh。

.PARAMETER RemoteMeshDir
  远端存放插件源码的目录 (会挂进容器的 /opt/mesh)。

.PARAMETER RemoteProjectDir
  远端本 pack 的目录, 里面要有 docker-compose.yml 与 docker-compose.dev.yml。

.EXAMPLE
  ./scripts/sync-mesh.ps1

.EXAMPLE
  $env:DSH_SSH_HOST = 'dsh-server'
  ./scripts/sync-mesh.ps1 -SkipBuild
#>
[CmdletBinding()]
param(
  [string] $SshHost = $(if ($env:DSH_SSH_HOST) { $env:DSH_SSH_HOST } else { 'dsh-server' }),
  [string] $LocalRepo = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'dsh-workspace-mesh'),
  [string] $RemoteMeshDir = '/srv/dsh-workspace-mesh',
  [string] $RemoteProjectDir = '~/harness-deploy',
  [switch] $SkipBuild
)

# ssh/scp 会把警告写到 stderr, 合并进管道后会变成 ErrorRecord;
# 这里统一用显式的 $LASTEXITCODE 判定成败, 所以不让它升级成终止错误。
$ErrorActionPreference = 'Continue'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Note($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

if (-not (Test-Path (Join-Path $LocalRepo 'package.json'))) {
  throw "找不到本地插件仓库: $LocalRepo (用 -LocalRepo 指定)"
}

Write-Step "检查远端连通性 (SSH 别名: $SshHost)"
& ssh -o BatchMode=yes -o ConnectTimeout=10 $SshHost 'true' 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "连不上 $SshHost。请先在本机 ~/.ssh/config 里配好这个 Host 别名 (仓库里不写具体地址), 或用 -SshHost 指定别的别名。"
}

if (-not $SkipBuild) {
  Write-Step "本地构建: pnpm build"
  Push-Location $LocalRepo
  try {
    & pnpm build 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "pnpm build 失败" }
  } finally {
    Pop-Location
  }
} else {
  Write-Note "跳过构建 (-SkipBuild), 直接同步现有 lib/"
}

if (-not (Test-Path (Join-Path $LocalRepo 'lib/index.js'))) {
  throw "本地没有 lib/index.js, 先跑 pnpm build"
}

# scp 用正斜杠路径最稳
$libDir = (Join-Path $LocalRepo 'lib') -replace '\\', '/'

Write-Step "同步构建产物 -> ${SshHost}:$RemoteMeshDir"
# /srv 这类目录通常要 root 建; 建完把属主给当前用户, 后面的 scp 才能写。
# 用单引号 + -f, 免得 PowerShell 把远端的 $(id -u) 给展开了。
$prep = 'sudo mkdir -p "{0}" && sudo rm -rf "{0}/lib" && sudo chown -R $(id -u):$(id -g) "{0}"' -f $RemoteMeshDir
& ssh -t $SshHost $prep 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw "远端准备目录失败" }

& scp -r $libDir "${SshHost}:$RemoteMeshDir/" 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw "同步 lib/ 失败" }

foreach ($file in @('package.json', 'cordis.patch.yml')) {
  $src = Join-Path $LocalRepo $file
  if (-not (Test-Path $src)) { throw "本地缺少 $file" }
  & scp $src "${SshHost}:$RemoteMeshDir/" 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "同步 $file 失败" }
}

Write-Step "远端: 写入 .env 并以 dev 覆盖层重启"
$remote = @"
set -e
cd $RemoteProjectDir
grep -q '^DSH_MESH_SRC=' .env 2>/dev/null || echo 'DSH_MESH_SRC=$RemoteMeshDir' >> .env
COMPOSE='docker compose -f docker-compose.yml -f docker-compose.dev.yml'
sudo $COMPOSE up -d
sudo $COMPOSE restart dsh
sleep 4
sudo $COMPOSE logs --tail=80 dsh 2>/dev/null | grep -i -E 'mesh|\[dev\]' | tail -20 || true
"@
& ssh -t $SshHost $remote 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw "远端重启失败" }

Write-Step "完成"
Write-Note "若日志里没有 [dev] linked, 常见原因: pnpm 不在容器 PATH(需在 Dockerfile 补 npm install -g pnpm 重建镜像)或远端还没 git pull 到 docker-compose.dev.yml"
