# 开发指南：用这个 pack 做开发

本文是**唯一入口**的实操文档：从零部署、日常迭代、开发插件、配密钥、排错。
面向"要在这个仓库上继续改东西的人"，不是给最终用户看的安装说明（那份在 README）。

---

## 0. 先理解四层结构

| 层 | 文件 | 作用 |
|---|---|---|
| 镜像层 | `Dockerfile` | node:22-slim + 全局 dsh + pnpm；改它必须重建镜像 |
| 编排层 | `docker-compose.yml` | 卷、端口、容器启动命令（bootstrap 引导） |
| 流水线层 | `.cnb.yml` | push → 构建镜像 → 推制品库 → SSH 部署到服务器 |
| 插件层 | `bootstrap/`、`bootstrap-dev/` | 预装插件：前者装发布物，后者装源码 |

**两条链路，别混用：**

| 链路 | 用在哪 | 改代码要做什么 | 需要重建镜像 |
|---|---|---|---|
| 发布链路 | 所有人 | 改 `bootstrap/10-plugins.sh` 的包名 | 是 |
| 开发链路 | 只给插件作者 | 同步构建产物 + 重启容器 | 否 |

判定口诀：**在 `/opt/bootstrap` 里的跟镜像走，在 `/opt/dev` 里的跟仓库走。**

---

## 1. 前置条件

**服务器**：Docker + Compose v2；一个能 SSH 的普通用户（默认 `ubuntu`）；该用户能 `sudo -n docker`（无密码 sudo）。

**本机**：`git`、`ssh`；Windows 上开发插件还需要 PowerShell 7（`pwsh`）。

**CNB**：仓库 `cnb.cool/<你>/oh-my-dsh-pack` 是**权威源**。GitHub 不参与构建、不参与部署。

---

## 2. 首次部署

```bash
# 服务器上
git clone https://cnb.cool/<你>/oh-my-dsh-pack.git ~/harness-deploy
cd ~/harness-deploy
sudo docker compose up -d
sudo docker compose logs dsh | grep 'dsh web:'   # 拿带 token 的登录 URL
```

首次启动会从 dsh 自带模板初始化 web profile，然后跑 `bootstrap/*.sh`。

---

## 3. 日常：改代码 → 打 tag → 上线

**日常 push 不会部署**，只做一次构建验证（证明 Dockerfile 还能构建）。

```bash
# 1) 日常开发：随便推，不会动生产
git add -A && git commit -m "..."
git push cnb main

# 2) 要上线了：打 tag，才会构建 + 推镜像 + 部署
git tag v0.1.0
git push cnb v0.1.0
```

打 tag 触发的流水线做三件事：构建镜像（`:latest` 与 `:v0.1.0`）→ 推 `docker.cnb.cool` →
SSH 上服务器执行 `~/bin/dsh-deploy.sh`（git pull → docker login → compose pull → up -d）。

**为什么改成 tag 触发**：push 频率高，每次都动生产等于没有发布会话；tag 是一个明确的"要上线了"的信号，
而且 tag 名同时成为镜像 tag，回滚时有据可查。

**验证"真的部署了"（不要只看 success）：**

```bash
# 流水线里 deploy 阶段的日志应当出现：
#   [deploy] git pull ... / docker login / compose pull / compose up -d / ps
# 服务器上核对
git -C ~/harness-deploy log --oneline -1     # 应等于被打 tag 的那个 commit
docker compose ps                            # 应 healthy
docker logs harness-dsh | grep '\[bootstrap\]'
```

**回滚**：把 `docker-compose.yml` 的 image 指向 `:v0.1.0` 这种具体 tag，或重新打一个指向旧提交的 tag。

> 历史坑：deploy 阶段曾经用 GitLab 的 `from_secret` 写法，CNB 不认识，变量恒为空，
> 脚本 `exit 0` 跳过，流水线显示 success 但什么都没部署。现在缺变量会 `exit 1`。

---

## 4. 开发插件（免发布迭代）

**适用场景**：你手上有插件源码，想改一行就看见效果，而不是每个版本发一次 npm 包。

### 4.1 一次性准备

1. 服务器上放源码目录（只放构建产物即可）：
   ```bash
   sudo mkdir -p /srv/dsh-workspace-mesh && sudo chown -R ubuntu /srv/dsh-workspace-mesh
   ```
2. 用 dev 覆盖层启动（挂载源码 + dev 脚本）：
   ```bash
   cd ~/harness-deploy
   sudo docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
   ```
3. 容器启动时 `bootstrap-dev/20-link-plugins.sh` 会把 `/opt/mesh` 用 `link:` 规格装进 web profile。
   验证：日志出现 `[dev] linked: /opt/mesh`，网页插件页出现该插件。

### 4.2 每轮迭代（约十几秒）

```bash
# 本机
cd E:/git/dsh-workspace-mesh && pnpm build
pwsh -File E:/git/oh-my-dsh-pack/scripts/sync-mesh.ps1
```

脚本做三件事：`scp` 构建产物 → 远端写入 `DSH_MESH_SRC` → 以 dev 覆盖层 `up -d` 并重启。
插件代码改动需要重启 dsh 进程；只改配置在开启 HMR 时可热生效。

### 4.3 为什么 `link:` 能生效

`dsh plugin add` 跑完 pnpm 后会 reconcile：新装的包若声明了 `dsh.bundle`（自带 `cordis.patch.yml`），
会被写进 profile 的 `dsh.profile.bundles`，并按它的 patch 组合出对应行，插件随之挂载。

### 4.4 回滚

```bash
cd ~/harness-deploy && sudo docker compose up -d     # 不带 dev 覆盖层，回到标准部署
```
profile 里会留下一个悬空的 link 依赖，插件页报错但不致命；要清干净：
`dsh plugin --profile web remove <包名>`。

---

## 5. 密钥：CNB 密钥仓库

**CNB 没有 `from_secret`。** 敏感值必须放在「密钥仓库」，再用 `imports` 注入成环境变量。

密钥仓库的限制（平台设计，绕不过去）：禁止 clone 到本地、禁止本地 push，**只能 Web 编辑**。
所以私钥永远不经过任何本地环境。

### 5.1 建仓库与文件

仓库类型选**密钥仓库**，例如 `ChenXu233/secrets`，根目录建 `dsh-deploy.yml`：

```yaml
DEPLOY_HOST: "服务器地址"

DEPLOY_SSH_KEY: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  ...
  -----END OPENSSH PRIVATE KEY-----

allow_slugs:
  - ChenXu233/oh-my-dsh-pack
allow_branches:
  - main
allow_events:
  - push
```

### 5.2 在流水线里引用

```yaml
main:
  push:
    - services: [docker]
      imports:
        - https://cnb.cool/ChenXu233/secrets/-/blob/main/dsh-deploy.yml
      stages: [...]
```

### 5.3 权限收紧要点

- 声明 `allow_*` 后，系统**忽略触发者角色**，只按规则校验；规则不匹配就没人能用（包括你自己）。
- 最小集：`allow_slugs`（限定仓库）+ `allow_branches`（限定分支）+ `allow_events`（限定 push）。
- 轮换：在密钥仓库 Web 界面改内容即可，所有引用它的流水线自动拿到新值。

---

## 6. 部署密钥的权限边界

服务器 `~/.ssh/authorized_keys` 里那把 key 长这样：

```
restrict,command="/home/ubuntu/bin/dsh-deploy.sh" ssh-ed25519 AAAA... cnb-deploy
```

- `restrict`：禁 pty、禁端口转发、禁 agent 转发、禁 X11。
- `command=`：不管客户端发什么命令，只执行这一个脚本；拿不到 shell。
- 已实测：`ssh -i key host 'echo PWNED; id; cat /etc/shadow'` 只会跑部署脚本。

**边界要说清**：脚本里有 `sudo docker`，而 docker 等价于 root 级能力。这没法再收窄（部署本来就需要 docker），
收窄的方式是"脚本内容固定"——这把 key 只能按下这个按钮。

**手工部署**（等价于 CI 那段）：
```bash
ssh -i ~/.ssh/cnb_deploy ubuntu@<服务器地址>
```

---

## 7. 排错表

| 症状 | 原因 | 修法 |
|---|---|---|
| 流水线在 deploy 阶段红 | 密钥文件缺 `DEPLOY_SSH_KEY`/`DEPLOY_HOST` | 看日志 ERROR 行，补密钥仓库 |
| imports 报 404/403 | slug、分支或 `allow_*` 不匹配 | 核对 URL 与 allow 规则 |
| 流水线绿但服务器没变 | 阶段被跳过（历史写法 `exit 0`） | 现在会 exit 1；查 deploy 阶段日志 |
| `git pull` 失败 | origin 指向已不存在的仓库 | `git remote set-url origin https://cnb.cool/<你>/oh-my-dsh-pack.git` |
| 容器里 `[bootstrap]` 没打印 | compose 把 `$VAR` 插值打空 | entrypoint 里的 shell 变量必须写 `$$VAR` |
| 插件装上不生效 | `engines.dsh` 不兼容 / 未 reconcile | 插件页看错误，或加版本豁免 |
| `dsh plugin` 报 pnpm 缺失 | 镜像没装 pnpm | Dockerfile 里 `npm install -g pnpm@11` |

---

## 8. 每次改动后的验收清单

- [ ] 流水线绿，且 deploy 阶段日志有 `[deploy] ps` 输出
- [ ] 服务器 `git log -1` == CNB main
- [ ] `docker compose ps` 显示 healthy
- [ ] `docker logs harness-dsh` 有 `[bootstrap]`（改插件时还要有 `[dev]`）
- [ ] 仓库里没有任何主机地址、密钥、私有仓库地址

---

## 9. 明确不做的事

- **不再用 GitHub 部署**。避免和 CNB 竞争推送；GitHub 侧的历史仓库（harness-deploy）已不存在。
- **不在仓库里放密钥**。密钥只进 CNB 密钥仓库。
- **不让 `bootstrap/` 承担开发迭代**。它进镜像，改一次就要重建一次。
