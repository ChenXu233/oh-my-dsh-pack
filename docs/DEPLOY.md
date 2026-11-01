# 部署与运维

面向要上线、回滚、排错的人。方向选型见 [PLANS.md](PLANS.md)；对外安装说明见 README。

## 0. 结构

| 层 | 在哪 | 改它要做什么 |
|---|---|---|
| 环境 | `Dockerfile` | 重建镜像 + 打 tag |
| 方向 | `plans/<方向>/` | `git pull` + 重启容器（挂载，不重建镜像） |
| 实例 | `docker-compose.yml` / `docker-compose.dev.yml` | `git pull` + `up -d` |
| 启动逻辑 | `entrypoint.sh` / `scripts/plan-boot.sh` | 重建镜像 + tag |
| 状态 | named volumes | 不动 |

判定口诀：**环境进镜像，方向进挂载，状态进卷；只有环境变了才重建。**

## 1. 前置条件

**服务器**：Docker + Compose v2；一个能 SSH 的普通用户（默认 `ubuntu`）；该用户能 `sudo -n docker`。
**本机**：`git`、`ssh`；Windows 上开发插件还需要 PowerShell 7（`pwsh`）。
**CNB**：仓库 `cnb.cool/<你>/oh-my-dsh-pack` 是权威源；GitHub 只是镜像。

## 2. 首次部署

```bash
git clone https://cnb.cool/<你>/oh-my-dsh-pack.git ~/harness-deploy
cd ~/harness-deploy
sudo docker compose up -d                 # 默认 full
# 或者选方向：sudo ./scripts/up.sh chat
sudo docker compose logs dsh | grep 'dsh web:'   # 拿带 token 的登录 URL
```

首次启动从 dsh 模板初始化 profile，然后 `scripts/plan-boot.sh` 按方向装插件、启动。

## 3. 日常发布

**push 不会部署**，只做构建验证 + 同步 GitHub 镜像。

```bash
git add -A && git commit -m "..."
git push cnb main          # 验证：只构建 capable
git tag v0.2.0 && git push cnb v0.2.0   # 上线：构建两档 + 推 + 部署
```

tag 流水线：构建 `:latest`（capable）与 `:slim`（base）→ 推 `docker.cnb.cool` →
SSH 上服务器执行 `~/bin/dsh-deploy.sh`（git pull → docker login → compose pull →
`up -d --force-recreate`）。

为什么 `--force-recreate`：方向目录是挂载的，只改清单时镜像不变，`up -d` 不会
重启容器；强制重建才会重跑 entrypoint / plan-boot 并装新插件。

> 改了 `deploy/dsh-deploy.sh` 后，记得同步到服务器 `~/bin/dsh-deploy.sh`
> （受限 key 的 `command=` 指向那里）。

**验证真的部署了（不要只看 success）：**

```bash
git -C ~/harness-deploy log --oneline -1     # 应等于被打 tag 的 commit
sudo docker compose ps                       # 应 healthy
sudo docker logs harness-dsh | grep '\[plan\]'
```

## 4. 回滚

把 `docker-compose.yml` 的 `DSH_IMAGE` 指向具体 tag（如 `:v0.1.0` / `:v0.1.0-slim`），
或重新打一个指向旧提交的 tag。

## 5. 密钥：CNB 密钥仓库

CNB 没有 `from_secret`。敏感值放**密钥仓库**，用 `imports` 注入；仓库禁止 clone，
只能 Web 编辑。文件里用 `allow_slugs` / `allow_branches` / `allow_events` 声明最小范围。

```yaml
# ChenXu233/secrets 的 dsh-deploy.yml
DEPLOY_HOST: "服务器地址"
DEPLOY_SSH_KEY: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  ...
  -----END OPENSSH PRIVATE KEY-----
allow_slugs:
  - ChenXu233/oh-my-dsh-pack
allow_branches:
  - main
  - "v*"
allow_events:
  - push
  - tag_push
```

> `allow_branches` 检查的是 `CNB_BRANCH`：分支事件是分支名，tag 事件是 tag 名，
> 所以 `v*` 也要放行。`github-sync.yml` 同时被 push 和 tag 流水线引用，
> 它的 `allow_events` / `allow_branches` 同样要含 `tag_push` 和 `v*`。

服务器 `authorized_keys` 里的部署 key 带 `restrict,command="/home/ubuntu/bin/dsh-deploy.sh"`：
拿不到 shell，只能跑部署脚本。脚本里有 `sudo docker`，等价 root 级能力，收窄方式是
“脚本内容固定”。

## 6. 开发实例（只给插件作者）

```bash
./scripts/up.sh dev                                        # 起空白 dsh（独立栈）
pwsh -File scripts/sync-plugin.ps1 -Plugin <插件目录名>     # build → scp → 重启
docker compose -f docker-compose.dev.yml down -v           # 重置（连卷清掉）
```

开发实例是独立 project（`harness-dev`）、独立卷（`dsh-dev-*`）、独立端口（3211），
与生产栈互不影响。插件源码一个子目录一个包，放在 `/srv/dev-plugins`，由
`bootstrap-dev/20-link-plugins.sh` 逐个 `link:` 装进 `web` profile。
远程访问可给 Caddy 加一个 dev 子域，或在 `.env` 里填 `DSH_DEV_PUBLIC_URL`。

## 7. 排错

| 症状 | 原因 | 修法 |
|---|---|---|
| 流水线在 deploy 阶段红 | 密钥缺 `DEPLOY_SSH_KEY` / `DEPLOY_HOST` | 看 ERROR 行，补密钥仓库 |
| imports 报 404/403 | slug / 分支 / `allow_*` 不匹配 | 核对 URL 与 allow 规则 |
| 流水线绿但服务器没变 | 部署阶段被跳过 | 现在缺变量会 exit 1；查 deploy 日志 |
| tag 流水线在 Prepare 阶段红，报 `does not conform to allow_events` | 密钥仓库没放行 `tag_push`（或 `allow_branches` 没放行 `v*`） | 在密钥仓库 Web 编辑补上 |
| 改了清单没生效 | 容器没重启 | `sudo docker compose up -d --force-recreate` |
| 所有插件安装失败，pnpm 报 `ERR_PNPM_INVALID_DEPENDENCY_NAME` | 清单用了 `name version`（空格） | 改成 `name@version`，清掉 profile 里的坏 key 后重启 |
| 插件装上不生效 | `engines.dsh` 不兼容 / 未 reconcile | 插件页看错误，或加版本豁免 |
| `dsh plugin` 报 pnpm 缺失 | 镜像没装 pnpm | Dockerfile 里 `npm install -g pnpm@11` |
| dev 实例第一次 link 失败 | profile 还没落地 | 脚本已先 `--dump-config`；看 `[dev]` 日志 |

## 8. 上线验收

- [ ] 流水线绿，deploy 阶段日志有 `[deploy] ps`
- [ ] 服务器 `git log -1` == CNB main
- [ ] `docker compose ps` 显示 healthy
- [ ] `docker logs harness-dsh` 有 `[plan]`（开发实例还要有 `[dev]`）
- [ ] 仓库里没有任何主机地址、密钥、私有仓库地址
