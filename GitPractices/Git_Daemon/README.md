# Git 镜像加速节点

把 GitHub 上指定的仓库同步到自己的服务器，客户端用 `git://` 协议拉取，无需配置密钥。

## 脚本一览

| 文件                      | 用途                                                   |
| ------------------------- | ------------------------------------------------------ |
| `deploy-git-mirror.sh`    | 部署：创建 git 用户、安装同步脚本、配置服务与定时任务  |
| `uninstall-git-mirror.sh` | 卸载：停止服务并清理本部署生成的文件与定时任务         |
| `test-git-mirror.sh`      | 单元测试：只在本地测试脚本功能                 |

## 快速开始

### 1. 安装依赖

执行以下命令安装依赖：

```bash
sudo apt-get update
sudo apt-get install -y git curl sudo util-linux coreutils openssh-client iproute2
```

### 2. 下载脚本

```bash
curl -fsLO https://raw.githubusercontent.com/NEANC/PKB/master/GitPractices/Git_Daemon/{deploy,uninstall}-git-mirror.sh
```

用 wget 也可以：

```bash
wget -q https://raw.githubusercontent.com/NEANC/PKB/master/GitPractices/Git_Daemon/{deploy,uninstall}-git-mirror.sh
```

### 3. 部署

先查看全部参数：

```bash
bash deploy-git-mirror.sh --help
```

最小示例：镜像两个仓库，关闭可选的 hosts 更新。

```bash
sudo bash deploy-git-mirror.sh \
  --repos "git/git,octocat/Hello-World" \
  --listen 0.0.0.0 \
  --port 9418 \
  --hosts no
```

部署会创建 git 用户、写入配置、安装 systemd 服务，并立即同步一次。完成后终端会打印可直接复制使用的克隆命令。

### 下载并一次完成部署

```bash
curl -fL 'https://raw.githubusercontent.com/NEANC/PKB/master/GitPractices/Git_Daemon/deploy-git-mirror.sh' | sudo bash -s -- --repos octocat/Hello-World --listen 0.0.0.0 --port 9418 --hosts no --no-cron

wget -qO- 'https://raw.githubusercontent.com/NEANC/PKB/master/GitPractices/Git_Daemon/deploy-git-mirror.sh' | sudo bash -s -- --repos octocat/Hello-World --listen 0.0.0.0 --port 9418 --hosts no --no-cron
```

## 验证部署

在服务器上确认服务状态和仓库可读：

```bash
sudo systemctl status git-daemon --no-pager
git ls-remote git://127.0.0.1:9418/git/git.git HEAD
```

从客户端测试，把 `mirror.example.com` 换成服务器的域名或 IPv4：

```bash
git ls-remote git://mirror.example.com:9418/git/git.git HEAD
git clone git://mirror.example.com:9418/git/git.git
```

## 克隆仓库

仓库保存在服务器 `/srv/git-mirror/<owner>/<repo>.git`，只提供读取，不支持推送。克隆地址使用完整路径：

```bash
git clone git://mirror.example.com:9418/octocat/Hello-World.git
```

部署脚本只做两件事：把仓库同步到对应目录，并在仓库里写一个 `git-daemon-export-ok` 标记。**凡是带这个标记的仓库，都能通过它所在的路径被匿名读取**；没有标记的仓库不会对外提供。

## 短名访问（可选）

如果觉得 `owner/repo` 太长，可以手动建一个符号链接（symlink），用更短的地址访问：

```bash
git clone git://mirror.example.com:9418/Hello-World.git
```

脚本不会自动创建短名。原因是不同作者常有同名仓库（如 `alice/demo` 和 `bob/demo`），自动挑选一个会造成意外的混淆，交给你决定更稳妥。

### 创建步骤

```bash
# 1. 确认仓库已同步，并带有发布标记
sudo test -f /srv/git-mirror/octocat/Hello-World.git/git-daemon-export-ok && echo 已发布

# 2. 确认短名没有被占用（提示 No such file or directory 说明可用）
ls -ld /srv/git-mirror/Hello-World.git

# 3. 用 git 用户创建相对路径符号链接
sudo -u git ln -s -- ./octocat/Hello-World.git /srv/git-mirror/Hello-World.git
```

### 规则

- 链接名必须是仓库短名加 `.git`，例如 `Hello-World.git`。
- 链接目标必须写成相对路径 `./<owner>/<repo>.git`，相对 `/srv/git-mirror`，不要用绝对路径。
- 同一个短名只能指向一个仓库。已经用 `demo.git` 指向 `alice/demo` 后，`bob/demo` 只能继续用完整路径。

### 验证与删除

```bash
# 验证链接
sudo -u git ls -l /srv/git-mirror/Hello-World.git
git ls-remote git://mirror.example.com:9418/Hello-World.git HEAD

# 想取消短名时删除链接（只删链接，不动仓库本身）
sudo rm -- /srv/git-mirror/Hello-World.git
```

## 配置要同步的仓库

`--repos` 与 `--repos-file` 二选一。

### 使用 `--repos`

逗号分隔仓库，全部按完整镜像处理，包含所有分支和标签：

```bash
sudo bash deploy-git-mirror.sh --repos "git/git,octocat/Hello-World" --hosts no
```

建议只写 `owner/repo`，不要带 `.git`。

### 使用 `--repos-file`

逐行配置，可以只同步指定分支。每行格式为 `owner/repo [branch1,branch2,...]`，`#` 之后的内容是注释：

```text
# 完整镜像：所有分支和标签
octocat/Hello-World

# 只同步一个分支
git/git master

# 只同步多个分支
torvalds/linux master,next,stable
```

```bash
sudo bash deploy-git-mirror.sh --repos-file /root/git-mirror/repos.list.source --hosts no
```

说明：

- 不写分支时同步仓库的全部引用；写了分支则只同步这些分支，不同步标签。
- 该文件需提前创建，部署时会被复制为 `/etc/git-mirror/repos.list`。之后改配置直接编辑这个生效文件即可，也可以重新部署覆盖它。
- 示例中的分支仅用于演示格式，请换成上游真实存在的分支，否则该仓库本次同步会失败。

## 部署参数

| 参数             | 说明                                                           |
| ---------------- | -------------------------------------------------------------- |
| `--repos`        | 与 `--repos-file` 二选一；逗号分隔的仓库列表，全部按完整镜像处理 |
| `--repos-file`   | 与 `--repos` 二选一；逐行指定完整镜像或分支列表                 |
| `--scripts-dir`  | 生成脚本的安装目录，默认 `/usr/local/bin`                       |
| `--no-cron`      | 不写入或修改同步 cron 和 hosts cron                             |
| `--port`         | 监听端口，默认 `9418`，范围 1-65535                             |
| `--listen`       | 监听地址，默认 `0.0.0.0`                                        |
| `--proxy`        | 上游 HTTPS 代理，默认空                                         |
| `--github-token` | 可选 GitHub HTTPS 凭据，默认空                                  |
| `--ssh`          | 是否启用 SSH 回退，默认 `no`                                    |
| `--ssh-key`      | SSH 私钥路径，默认 `/home/git/.ssh/id_ed25519_mirror`           |
| `--cron`         | 同步频率，默认 `0 * * * *`，即每小时                            |
| `--hosts`        | 是否安装并执行第三方 GitHub hosts 更新，默认 `yes`              |
| `--hosts-cron`   | hosts 更新时间，默认 `0 3 * * *`，即每天 03:00                  |
| `--hosts-url`    | hosts 数据源，默认 GitHub520 主数据源                           |

cron 时间使用服务器配置的时区。

### 自定义脚本目录

默认安装到 `/usr/local/bin`，可用 `--scripts-dir` 指定其他绝对目录：

```bash
sudo bash deploy-git-mirror.sh --repos-file /root/git-mirror/repos.list --scripts-dir /opt/git-mirror/bin --hosts no
```

- 目录须为绝对路径且不以 `/` 结尾，并保证 git 用户可访问。
- 不要放到 `/root`、`/home` 等被 systemd `ProtectHome` 隔离的位置。
- 路径中只使用字母、数字、`/`、`.`、`_` 和 `-`。
- 重新部署不会自动清理旧目录中的脚本和旧 cron，需要核对后手动删除。

### 不配置定时任务

`--no-cron` 会跳过所有定时任务，但仍然执行一次同步。之后需要自行调度：

```bash
sudo -u git -H /usr/local/bin/git-mirror-sync.sh
```

使用了 `--scripts-dir` 时，请替换为实际安装路径。

## 注意事项

- **凭据：** `--github-token` 会以明文写入 `/etc/git-mirror/mirror.env`，权限 600，可能出现在进程参数和错误日志中。公开仓库不需要 token；也不要用能读取私有仓库的凭据，把私有内容发布到匿名镜像上。
- **hosts：** `--hosts yes` 是默认值，会用第三方数据源改写系统 `/etc/hosts` 并清理已有的 GitHub 相关记录。已有自定义记录、或不需要该功能时，请传 `--hosts no`。
- **安全边界：** `git://` 没有身份认证和传输加密，只适合镜像允许匿名读取的仓库。服务只发布带 `git-daemon-export-ok` 标记的仓库，这**不是用户认证机制**；需要限制访问来源时请用防火墙。
- **镜像范围：** 只镜像 Git 对象和引用，不包含 Issues、Release 附件和 Git LFS 对象，子模块也不会改写为本地镜像地址。

## 日常维护

| 路径                                     | 内容                             |
| ---------------------------------------- | -------------------------------- |
| `/etc/git-mirror/mirror.env`             | 上游代理、凭据和 SSH 配置        |
| `/etc/git-mirror/repos.list`             | 实际生效的逐行仓库和分支配置     |
| `/etc/git-mirror/install.paths`          | 部署时记录的脚本路径和 cron 状态 |
| `/srv/git-mirror`                        | 镜像仓库及手动的短名链接         |
| `/etc/systemd/system/git-daemon.service` | 服务定义                         |
| `/var/log/git-mirror/sync.log`           | 同步日志                         |
| `/var/log/git-mirror/hosts.log`          | hosts 更新日志，启用该功能时才有 |

常用操作：

```bash
# 手动同步一次
sudo -u git -H /usr/local/bin/git-mirror-sync.sh

# 查看定时任务
sudo crontab -u git -l
sudo crontab -l

# 实时查看同步日志
tail -f /var/log/git-mirror/sync.log
```

修改仓库列表后运行一次同步脚本即可生效。同步结束后，控制台和日志会按仓库分组输出各分支的提交报告，便于核对结果。

脚本提示「部署完成」不代表所有仓库都同步成功，请以同步日志为准。

## 更新已有部署

不支持，脚本只会执行一次覆盖安装，未提供的参数会回到脚本默认值。

## 卸载

默认删除镜像、日志和配置，保留 git 用户，并需要终端确认：

```bash
sudo bash uninstall-git-mirror.sh
```

保留镜像、日志、hosts 记录和 git 用户：

```bash
sudo bash uninstall-git-mirror.sh --keep-data --keep-hosts --keep-user
```

此时服务、脚本和配置目录仍会被删除，`--keep-data` 不代表保留 `/etc/git-mirror`。只有确认 git 用户没被其他服务使用时，才考虑 `--remove-user`；`--yes` 跳过交互确认，不代表操作没有风险。

也可以不下载脚本直接卸载，管道会占用标准输入，确认步骤会被跳过：

```bash
curl -fsL 'https://raw.githubusercontent.com/NEANC/PKB/master/GitPractices/Git_Daemon/uninstall-git-mirror.sh' | sudo bash -s -- --keep-hosts
```

若同步任务仍在运行，卸载会中止。防火墙和云安全组规则需要自行清理。
