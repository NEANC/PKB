# Git 镜像直连节点

将指定 GitHub 仓库同步为本地裸镜像，通过 `git-daemon` 向客户端提供只读 Git 协议访问。

部署和卸载脚本不生成、修改或重载它们的配置，也不依赖 Docker。

## 文件说明

| 文件                      | 用途                                                   |
| ------------------------- | ------------------------------------------------------ |
| `deploy-git-mirror.sh`    | 创建用户、安装同步脚本和访问钩子、配置 systemd 与 cron |
| `uninstall-git-mirror.sh` | 停止服务并清理本部署的文件和定时任务                   |
| `test-git-mirror.sh`      | 检查 Bash 语法、直连配置、卸载保护及访问钩子行为       |

## 工作方式

客户端使用 `git://服务器:9418/repo.git` 直接访问 git-daemon。

服务器从 GitHub 同步仓库时，依次尝试已配置的 HTTPS 代理、HTTPS 直连和可选的 SSH 回退。`--proxy` 只用于服务器访问上游，与客户端访问镜像的路径无关。

- 默认监听 `0.0.0.0:9418`，即全部 IPv4 接口。
- 使用 `--listen` 指定监听地址，使用 `--port` 指定端口。
- 不再使用内部转发端口或双端口设计。
- 只提供读取，显式禁止 `receive-pack`，客户端不能推送。
- 仓库保存为 `/srv/git-mirror/owner/repo.git`，通过顶层短名链接提供访问。
- 客户端使用 `/repo.git`，不要使用 `/owner/repo.git`。

**安全边界：** `git://` 没有身份认证和传输加密。只镜像允许匿名读取的仓库，并按需要限制防火墙来源 IP。访问钩子限制路径，不是用户身份认证机制。

## 运行环境

部署和卸载在使用 systemd 的 Linux 服务器上以 root 或 sudo 执行，不要在 Windows 开发机上执行实际部署。

建议使用 Debian/Ubuntu。当前创建用户的命令采用 Debian 风格；虽然安装依赖包含 yum 分支，不代表已验证其他发行版的完整部署流程。

运行前确保具备：

- Bash、Git、curl、sudo。
- systemd 及 `systemctl`。
- cron 服务及 `crontab`。
- `flock`、awk、sed、grep、find 等工具。
- 启用 SSH 回退时需要 SSH 客户端和 git 用户可读取的私钥。

脚本会尝试安装缺失的 Git/curl，其他依赖需预先准备。Debian/Ubuntu 可按需安装：

```bash
sudo apt-get update
sudo apt-get install -y git curl sudo cron util-linux coreutils openssh-client
sudo systemctl enable --now cron
```

请保留 Shell 文件的 LF 换行符，并使用 `bash` 执行，不要使用 `sh`。

## 部署

先检查参数：

```bash
bash deploy-git-mirror.sh --help
```

首次部署示例，关闭可选的第三方 hosts 更新：

```bash
sudo bash deploy-git-mirror.sh \
  --repos "git/git,LmeSzinc/AzurLaneAutoScript" \
  --listen 0.0.0.0 \
  --port 9418 \
  --hosts no
```

### 按分支同步

使用 `--repos-file` 可以逐行配置仓库。每行格式为 `owner/repo [branch1,branch2,...]`，`#` 后面的内容为注释：

```text
# 完整镜像：所有分支、标签和其他 refs
LmeSzinc/AzurLaneAutoScript

# 只同步单个分支
git/git master

# 只同步多个分支
torvalds/linux master,next,stable
```

行为规则：

- 省略分支时，使用 `+refs/*:refs/*`，同步所有 refs，包括分支和标签。
- 指定分支时，只配置对应的 `refs/heads/<branch>`，并使用 `--no-tags`，不会自动同步标签。
- 分支配置更新后，脚本只会在成功获取新内容后删除不再选择的本地 refs；网络或获取失败不会先清理已有内容。
- 指定分支模式时，裸仓库的 `HEAD` 指向配置中第一个分支。
- 仓库名必须是合法的 `owner/repo`，分支名使用 Git 合法 ref 名称；不支持 `refs/*`、通配符、空分支项或带空格的分支列表。

```bash
sudo bash deploy-git-mirror.sh \
  --repos-file /etc/git-mirror/repos.list.source \
  --port 9418
```

`--repos` 与 `--repos-file` 不能同时使用。使用 `--repos` 时，逗号分隔的每个仓库均按完整镜像处理。

### 生成脚本安装到其他目录

默认生成到 `/usr/local/bin`。可以使用 `--scripts-dir` 改为其他绝对目录，例如：

```bash
sudo bash deploy-git-mirror.sh \
  --repos-file /root/git-mirror/repos.list \
  --scripts-dir /opt/git-mirror/bin \
  --hosts no
```

部署会将以下脚本写入该目录：

- `git-mirror-sync.sh`
- `git-access-hook.sh`
- `update-github-hosts.sh`（启用 hosts 更新时）

实际路径会记录在 `/etc/git-mirror/install.paths`，卸载脚本会从该文件读取，不会只删除 `/usr/local/bin` 下的默认脚本。自定义目录应是绝对路径且不要使用会被其他服务共享的危险目录。

### 不配置 cron

使用 `--no-cron` 时，部署不会写入或修改 git 用户及 root 的 cron；hosts 脚本仍可安装并在部署期间执行一次，但不会创建 hosts 定时任务：

```bash
sudo bash deploy-git-mirror.sh \
  --repos-file /root/git-mirror/repos.list \
  --no-cron
```

此模式下需要你通过其他调度器调用同步脚本，例如 systemd timer、外部任务平台或手动执行：

```bash
sudo -u git -H /opt/git-mirror/bin/git-mirror-sync.sh
```

如果目标主机已经存在由旧部署创建的相同脚本 cron，`--no-cron` 不会自动删除旧任务；请确认后手动移除，避免旧任务继续执行。

`--repos` 使用逗号分隔的 `owner/repo`，建议不要附加 `.git`。不同 owner 下的仓库短名也必须唯一，例如不要同时发布 `alice/demo` 和 `bob/demo`；当前扁平链接不能区分同名仓库。

### 主要参数

| 参数             | 默认值或说明                                               |
| ---------------- | ---------------------------------------------------------- |
| `--repos`        | 与 `--repos-file` 二选一；逗号分隔的仓库列表，全部按完整镜像处理 |
| `--repos-file`   | 与 `--repos` 二选一；逐行指定完整镜像或分支列表                 |
| `--scripts-dir`  | `/usr/local/bin`，生成脚本的绝对目录                           |
| `--no-cron`      | 不写入或修改同步 cron 和 hosts cron                           |
| `--port`         | `9418`，范围 1–65535；非 root 服务使用低端口还需要额外权限     |
| `--listen`       | `0.0.0.0`，监听地址                                        |
| `--proxy`        | 空，不使用上游 HTTPS 代理                                  |
| `--github-token` | 空，可选 GitHub HTTPS 凭据                                 |
| `--ssh`          | `no`，是否启用 SSH 回退                                    |
| `--ssh-key`      | `/home/git/.ssh/id_ed25519_mirror`                         |
| `--cron`         | `0 * * * *`，每小时同步                                    |
| `--hosts`        | `yes`，是否安装并执行第三方 GitHub hosts 更新              |
| `--hosts-cron`   | `0 3 * * *`，每天 03:00 更新 hosts                         |
| `--hosts-url`    | 脚本配置的 GitHub520 主数据源                              |

cron 时间使用服务器配置的时区。

**凭据注意事项：** 当前同步实现会将 GitHub token 拼入 HTTPS URL，可能留在镜像的 origin 配置或错误输出中；不要分享相关配置、日志或仓库配置文件。公开仓库通常不需要 token。不要用有权读取私有仓库的凭据将私有内容发布到匿名镜像服务。

**hosts 注意事项：** hosts 更新会修改系统 `/etc/hosts`，使用第三方数据源。当前更新脚本还会清理匹配 GitHub 等域名的已有记录；如果已有自定义记录或不需要该功能，请使用 `--hosts no`。此参数只控制本次安装及任务配置，不会自动移除旧部署已创建的 hosts 定时任务。

重复部署会重新写入仓库列表和配置文件，请先备份手工修改。已经下载的镜像不会因从仓库列表删除而自动删除或取消发布。

## 验证和客户端使用

默认监听配置下，在服务器上检查：

```bash
sudo systemctl status git-daemon --no-pager
sudo journalctl -u git-daemon -n 50 --no-pager
sudo ss -tlnp 'sport = :9418'
git ls-remote git://127.0.0.1:9418/git.git HEAD
```

指定了其他监听地址或端口时，相应替换命令中的地址和端口。

客户端验证与克隆：

```bash
git ls-remote git://mirror.example.com:9418/git.git HEAD
git clone git://mirror.example.com:9418/git.git
```

将 `mirror.example.com` 换成自己的域名或服务器 IPv4。部署完成后的终端提示会自动生成实际 IPv4 命令，不再使用地址占位符：

- 使用 `ip -o -4 addr show up` 从启用的网卡读取地址，忽略 IPv6，过滤回环、链路本地等不适合远程连接的地址并去重。
- 监听 `0.0.0.0` 时，本机验证使用 `127.0.0.1`；客户端克隆命令列出各网卡符合条件的 IPv4。
- 监听指定 IPv4 时，只输出与网卡地址匹配的监听 IP，不推荐其他网卡地址。
- 仅监听回环地址时，提示“仅本机访问”，不输出远程克隆命令。
- 没有可用 IPv4、网卡查询失败或缺少 `ip` 命令时，输出警告，不猜测客户端地址。非 IPv4 监听不生成 Git 地址命令，也不会改变服务原有监听设置。

自动检测依赖 iproute2，不访问公网 IP 查询服务。网卡上的内网地址不代表公网可达，多网卡时请按客户端所在网络选择，并确认路由、防火墙及必要的端口映射。

## 日常维护

| 路径                                     | 内容                           |
| ---------------------------------------- | ------------------------------ |
| `/etc/git-mirror/mirror.env`             | 上游代理、凭据和 SSH 配置 |
| `/etc/git-mirror/repos.list`             | 实际生效的逐行仓库/分支配置       |
| `/etc/git-mirror/install.paths`          | 部署时记录的实际脚本路径和 cron 状态 |
| `/srv/git-mirror`                        | 镜像仓库及短名链接                 |
| `<scripts-dir>/git-mirror-sync.sh`       | 同步脚本（默认 `/usr/local/bin`） |
| `<scripts-dir>/git-access-hook.sh`       | 只读短名访问钩子                 |
| `/etc/systemd/system/git-daemon.service` | 服务定义                         |
| `/var/log/git-mirror/sync.log`           | 同步日志                       |
| `<scripts-dir>/update-github-hosts.sh`  | 可选的 hosts 更新脚本（默认 `/usr/local/bin`） |
| `/var/log/git-mirror/hosts.log`          | 可选的 hosts 更新日志          |

手动同步和检查任务：

```bash
sudo -u git -H /usr/local/bin/git-mirror-sync.sh
# 使用 --scripts-dir 时替换为实际安装目录
sudo crontab -u git -l
sudo crontab -l
```

修改仓库列表后运行同步脚本。首次同步出现失败时，部署脚本会警告并继续；应检查同步日志，不能只凭部署完成提示判断仓库已可用。

### Git 执行时间与原生输出

- Git 同步不再使用脚本级 `timeout`，也不再生成或读取 `FETCH_TIMEOUT` 参数；移除了脚本额外指定的 SSH `ConnectTimeout`。系统、Git、SSH、代理或外部调度器自身的超时仍可能生效。
- `git fetch --progress` 显式显示 Git 原生进度，即使输出经过管道，也保留接收对象、解析增量等进度信息。
- Git 标准输出和标准错误先通过 `tee -a` 完整追加到 `/var/log/git-mirror/sync.log`，不覆盖已有日志；只有终端展示经过筛选。
- 终端隐藏格式明确的正常引用更新明细，包括新增分支、标签和其他引用、快进更新、强制更新、删除及已是最新的记录。`From ...` 来源行、下载进度、错误、警告、拒绝更新及无法识别的输出仍保留，不会截断来源行之后的全部内容。
- Git 原生进度的回车刷新保持不变；分支提交报告在 Git 命令结束后输出，不替代下载进度。筛选不改变同步范围和 Git 命令退出码。
- 使用 `tail -f` 查看的是完整日志，因此仍会看到被终端筛选隐藏的引用更新明细。
- 自动生成的 cron 仍将控制台输出重定向到 `/dev/null`，但同步脚本内部的日志追加不受影响。使用任务平台查看实时输出时，不要在平台命令外额外添加丢弃输出的重定向。
- 不设置强制时限意味着连接长期不退出时，同步会继续等待并持有同步锁；后续定时任务会跳过，回退路径要等当前 Git 命令失败返回后才会执行。
- 本次仅移除 Git 同步的脚本级时限，hosts 更新脚本中 curl 的连接和下载超时保持不变。

实时查看同步日志：

```bash
tail -f /var/log/git-mirror/sync.log
```

已部署服务器需要更新实际安装的同步脚本才能生效；旧配置文件中遗留的 `FETCH_TIMEOUT` 不再被新版同步逻辑使用。

### 每个分支的提交报告

每次仓库同步结束后，控制台和 `/var/log/git-mirror/sync.log` 按仓库分组显示提交报告。仓库名和同步状态只在报告标题显示一次；每个分支使用 `↳ 分支名: 短哈希 摘要`，下一行缩进显示带时区的提交者时间，不再将所有字段挤在一行。

- 短哈希以 12 位为起点，Git 在需要消除歧义时可自动延长。
- 完整镜像：按分支名排序，报告所有本地 `refs/heads/`；不将标签或其他 refs 当作分支。
- 指定分支：按配置顺序报告所选分支。
- 同步成功：标记“本次同步成功”，展示同步后的本地分支头。
- 同步失败：标记“本次同步失败”和“未确认上游最新”，展示可用的本地缓存，不将旧提交误报为最新。
- 缺失分支或空仓库：明确提示，不因没有可展示的提交而中断后续仓库处理。

提交时间不是同步时间，也不能单独证明内容最新。短哈希便于快速核对；严格比较时，可在服务器执行 `git --git-dir=/srv/git-mirror/owner/repo.git rev-parse refs/heads/master` 获取完整哈希，与上游对应分支比较（替换仓库路径和分支名）。同步完成后，上游仍可能产生新提交。本报告不额外请求上游进行实时哈希比对。

此功能位于部署脚本生成的同步脚本中。已部署服务器需要更新实际安装的 `git-mirror-sync.sh` 才会生效；仅修改本地部署脚本不会自动更新服务器文件。

本方案镜像 Git 对象和引用，不等于备份 GitHub 的 Issues、Release 附件或 Git LFS 对象；子模块也不会自动改写为本地镜像地址。

## 卸载

默认卸载会删除镜像、日志和配置，保留 git 用户，并要求确认：

```bash
sudo bash uninstall-git-mirror.sh
```

保留镜像、日志、hosts 记录和 git 用户：

```bash
sudo bash uninstall-git-mirror.sh --keep-data --keep-hosts --keep-user
```

此时服务、脚本和配置目录仍会被删除；`--keep-data` 不代表保留 `/etc/git-mirror`。

只有确认 git 用户没有被其他服务使用时，才考虑 `--remove-user`。`--yes` 跳过交互确认，不代表操作无风险。

卸载前会尝试获取同步锁；若同步仍在运行则中止。卸载不会批量终止其他 Git 进程，也不会管理 Web 服务器。hosts 清理只删除 GitHub520 管理标记段。防火墙及云安全组规则需自行清理。

## 本地回归检查

```bash
bash test-git-mirror.sh
```

检查不会执行部署或卸载，不会修改系统服务、cron 或 hosts。访问钩子测试使用项目目录内的临时文件，退出时清理。

测试覆盖脚本语法、代理配置移除、只读监听参数、卸载保护及访问钩子的允许/拒绝行为。它不替代 Linux 上的 systemd 部署测试、真实 Git 克隆测试和网络连通性验证。

### LXC 集成测试记录（2026-09-30）

测试环境：Debian 13 LXC、Git 2.47.3、Bash 5.2.37、systemd 257；使用独立测试端口 19418、自定义脚本目录及公开测试仓库 `octocat/Hello-World`。

已验证通过：

- Windows Git Bash 与 Linux 容器内的回归检查。
- 自定义脚本目录安装、systemd 服务启动和 TCP 直连监听。
- 已安装同步脚本的单分支及多分支同步；镜像与客户端查询的分支哈希一致。
- 容器内和外部客户端的 `ls-remote`；容器内实际克隆及 `git fsck --full`。
- 完整 `owner/repo` 路径被拒绝，短名访问成功。
- 缺失分支时同步返回失败，已有引用未改变，日志明确标记本地缓存。
- 分支日志使用短哈希、摘要和独立时间行。
- `--no-cron` 未创建任务；启用 cron 时写入指定计划和自定义脚本路径。未等待计划时间验证 cron 自动触发。
- 持有同步锁时卸载被拒绝，服务和数据不受影响。
- 保留数据卸载移除服务、脚本及 cron，同时保留完整镜像；后续完整清理移除测试镜像、日志和 git 用户，测试端口释放。

实测发现并修复：

- 卸载时以只读方式打开已有同步锁，避免共享目录文件保护阻止 root 以追加创建方式打开 git 用户的锁文件；未关闭内核保护。
- 只读 Git 服务设置 `HOME=/nonexistent` 和 `XDG_CONFIG_HOME=/nonexistent`，保留 `ProtectHome` 隔离。重新部署后实际克隆不再出现读取用户配置目录的权限警告。

验证限制：

- GitHub 完整 refs 拉取首次达到 180 秒超时，后续重新部署的拉取也出现等待；尚未确认根因。完整 refs、标签及模式切换仅通过本地裸仓库回归，不能视为远程完整镜像已验证通过。
- 本次关闭 hosts 更新，未验证其实际修改系统 hosts 的流程，也未验证代理、PAT、SSH 回退及 IPv6。
- 推送禁用通过配置和钩子测试检查，未执行实际网络推送测试。
- 部署脚本在首次同步失败后仍可启动服务并显示部署完成；必须结合同步日志、退出状态及实际引用判断镜像是否可用。

测试结束后已移除测试部署。测试证据保留在容器的临时测试目录中，安装或升级的系统依赖未回退；不能将测试容器视为恢复到测试前的完整快照。
