#Requires -Version 5.1
<#
.SYNOPSIS
  把一个本地插件仓库的构建产物同步到远端 dsh 实例并重启（免发布迭代）。

.DESCRIPTION
  远端目录约定: <RemotePluginsDir>/<Plugin>/  —— 一个插件一个子目录。
  容器里由 docker-compose.dev.yml 挂到 /opt/dev-plugins，再由
  bootstrap-dev/20-link-plugins.sh 遍历子目录逐个 link 安装。多插件互不干扰。

  远端主机用 SSH 别名（默认 dsh-server），仓库里不写具体地址。

.PARAMETER Plugin
  插件目录名。默认从 -LocalRepo 的 package.json 的 name 读取。

.PARAMETER LocalRepo
  本地插件仓库路径。默认: 本仓库同级的 <Plugin> 目录。

.EXAMPLE
  ./scripts/sync-plugin.ps1 -Plugin dsh-workspace-mesh

.EXAMPLE
  ./scripts/sync-plugin.ps1 -LocalRepo E:/git/dsh-another-plugin
#>
[CmdletBinding()]
param(
  [string] $Plugin = '',
  [string] $LocalRepo = '',
  [string] $SshHost = $(if ($env:DSH_SSH_HOST) { $env:DSH_SSH_HOST } else { 'dsh-server' }),
  [string] $RemotePluginsDir = '/srv/dev-plugins',
  [string] $RemoteProjectDir = '~/harness-deploy',
  [switch] $SkipBuild
)

$ErrorActionPreference = 'Continue'

function Write-Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Note($m) { Write-Host "    $m" -ForegroundColor DarkGray }

$repoRoot = Split-Path $PSScriptRoot -Parent

if (-not $LocalRepo) {
  if (-not $Plugin) { throw '至少给一个: -Plugin <名字> 或 -LocalRepo <路径>' }
  $LocalRepo = Join-Path (Split-Path $repoRoot -Parent) $Plugin
}
if (-not (Test-Path (Join-Path $LocalRepo 'package.json'))) { throw "找不到插件仓库: $LocalRepo" }
if (-not $Plugin) {
  $Plugin = (Get-Content (Join-Path $LocalRepo 'package.json') -Raw | ConvertFrom-Json).name
  if (-not $Plugin) { throw '无法从 package.json 读取 name' }
}

$remoteDir = "$RemotePluginsDir/$Plugin"

Write-Step "插件: $Plugin"
Write-Step "本地: $LocalRepo"
Write-Step "远端: ${SshHost}:$remoteDir"

& ssh -o BatchMode=yes -o ConnectTimeout=10 $SshHost 'true' 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "连不上 $SshHost (请在 ~/.ssh/config 配别名, 或用 -SshHost 指定)" }

if (-not $SkipBuild) {
  Write-Step '构建: pnpm build'
  Push-Location $LocalRepo
  try {
    & pnpm build 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'pnpm build 失败' }
  } finally { Pop-Location }
}

if (-not (Test-Path (Join-Path $LocalRepo 'lib/index.js'))) { throw '没有 lib/index.js, 先构建' }

$libDir = (Join-Path $LocalRepo 'lib') -replace '\\', '/'

Write-Step '准备远端目录'
$prep = 'sudo mkdir -p "{0}" && sudo rm -rf "{0}/lib" && sudo chown -R $(id -u):$(id -g) "{1}"' -f $remoteDir, $RemotePluginsDir
& ssh -t $SshHost $prep 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw '远端准备目录失败' }

Write-Step '同步产物'
& scp -r $libDir "${SshHost}:$remoteDir/" 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw '同步 lib/ 失败' }
foreach ($f in @('package.json', 'cordis.patch.yml')) {
  $src = Join-Path $LocalRepo $f
  if (-not (Test-Path $src)) { Write-Note "跳过缺少的 $f"; continue }
  & scp $src "${SshHost}:$remoteDir/" 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "同步 $f 失败" }
}

Write-Step '远端重启 (dev 覆盖层)'
$remote = @"
set -e
cd $RemoteProjectDir
grep -q '^DSH_DEV_PLUGINS=' .env 2>/dev/null || echo 'DSH_DEV_PLUGINS=$RemotePluginsDir' >> .env
COMPOSE='docker compose -f docker-compose.yml -f docker-compose.dev.yml'
sudo `$COMPOSE up -d
sudo `$COMPOSE restart dsh
sleep 4
sudo `$COMPOSE logs --tail=80 dsh 2>/dev/null | grep -i -E '\[dev\]' | tail -20 || true
"@
& ssh -t $SshHost $remote 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw '远端重启失败' }

Write-Step '完成'
Write-Note "日志里应出现 [dev] linked: $Plugin"
