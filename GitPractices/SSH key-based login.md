# SSH 密钥登录/无密登陆

如何在 Windows 环境下，为运行 Debian/Ubuntu 的服务器配置 SSH 密钥登录，并通过设置 SSH 别名，实现便捷登录。

> [!IMPORTANT]
> 本文默认使用 PWSH 7  
> 请不要使用 CMD / PWSH 5.1  
> 理论上已对 PWSH 5.1 做兼容，但不能保证可靠

> [!TIP]
> 推荐使用 ed25519 算法，产物更小，能更快链接服务器

## 1. 生成专属密钥对

执行命令，按提示操作：

```bash
# 创建 .ssh 文件夹
mkdir "$env:USERPROFILE\.ssh"
# -f 密钥保存路径/密钥文件名 -C "备注（可选，如服务器）"

# ed25519 密钥对（推荐）
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519 -C "服务器"

# rsa 密钥对（兼容性好）
ssh-keygen -t rsa -b 4096 -f $env:USERPROFILE\.ssh\id_rsa -C "服务器"
```

设置密码短语（可选，直接回车表示不设置密码）：  
在 `Enter passphrase (empty for no passphrase):` 提示下输入密码短语，有二次确认，后续登陆都需要该密码解密。

## 2. 确认密钥生成成功

成功生成后，在 `C:\Users\用户名\.ssh\` 目录下会出现两个文件：

- `id_ed25519` \ `id_rsa`：服务器专属**私钥**（妥善保管，勿泄露）；
- `id_ed25519.pub` \ `id_rsa.pub`：服务器专属**公钥**（需上传到服务器）。

## 3. 添加公钥到服务器

需将新生成的 `id_ed25519.pub` 上传到追加进入服务器 `~/.ssh/authorized_keys` 文件中。

### 3.1 在本机使用管道追加

直接在本机执行以下命令，将公钥追加到服务器的 `authorized_keys` 文件中：

```PowerShell
# 请注意替换公钥路径、用户名和IP地址
$pub = Join-Path $env:USERPROFILE '.ssh\id_ed25519.pub'
Get-Content -LiteralPath $pub |
  ssh <用户名>@<IP地址> "umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys"
```

### 3.2 在服务器中使用 `cat` 命令追加

登陆服务器后，执行以下命令：

```bash
# 创建 ~/.ssh 目录
mkdir -p ~/.ssh

# 将内容中的公钥追加到 authorized_keys 文件中
cat >> ~/.ssh/authorized_keys <<'EOF'
ssh-ed25519 AAAAxxxxxxxxxxxxxxxxxx xxx@xxx
EOF

# 设置权限
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

# 验证公钥是否追加成功
tail -n 1 ~/.ssh/authorized_keys
```

<details>
<summary>
更繁琐的方式：手动上传到服务器再追加
</summary>

### 3.3 手动上传到服务器再追加

1. 用 `scp` 上传新公钥到服务器 `/tmp` 目录：

```bash
scp C:\Users\用户名\.ssh\id_ed25519.pub <用户名>@<IP地址>:/tmp/
```

2. 登录服务器（输密码），配置公钥和权限：

```bash
# 登录服务器
ssh -p <端口> <用户名>@<IP地址>

# 创建 ~/.ssh 目录
mkdir -p ~/.ssh

# 将公钥追加到 authorized_keys 文件中，并自动打印
tee -a ~/.ssh/authorized_keys < /tmp/a.pub

# 设置权限
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

# 验证公钥是否追加成功
tail -n 1 ~/.ssh/authorized_keys

# 删除临时文件
rm /tmp/id_ed25519.pub
```

</details>

## 4. 设置本地 SSH 配置文件

进入 `C:\Users\你的用户名\.ssh\` 目录，创建或编辑 `config` 文件，并保存。

在 `config` 文件中添加以下内容：

```bash
# 服务器注释
Host 1.2.3.4 VPS vps 服务器             # 别名（可自定义，后续登录可使用这个别名；多个别名之间用空格隔开）
  HostName 1.2.3.4                     # 服务器IP或域名
  User username                        # 登录用户名
  # ProxyJump <跳板机别名>              # 如果需要跳板机，可取消注释并设置跳板机别名
  IdentityFile ~/.ssh/id_ed25519       # 私钥路径，若使用 SSH-Agent 管理 SSH 私钥时（如 BItwarden）可使用公钥指定。
  IdentitiesOnly yes                   # 使用指定的密钥
  Port 22                              # SSH端口
```

保存后使用 SSH 登陆测试

```bash
# 使用密钥登录
ssh -o IdentitiesOnly=yes <用户名>@<IP地址>

# 使用密码登录（若密钥无效）
ssh -o PubkeyAuthentication=no <用户名>@<IP地址>
```

> [!IMPORTANT]
> 必须确认 `ssh -o IdentitiesOnly=yes <用户名>@<IP地址>` 能够成功登录服务器，才能进行下一步安全性设置。

## 5. 安全性设置

```bash
# 备份原始配置
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# 编辑配置文件
sudo nano /etc/ssh/sshd_config
```

在配置文件设置：

```bash
# 启用证书/密钥认证
PubkeyAuthentication yes

# 禁用root登录（可选）
PermitRootLogin no

# 禁用密码认证，必须确保密钥认证已配置成功后再设置
PasswordAuthentication no

# 禁用空密码登录
PermitEmptyPasswords no

# 限制登录用户（可选）
AllowUsers your_username

# X11 转发（可选）：禁用跨网络使用远程服务器的图形程序
X11Forwarding no

# TCP 转发（可选）：关闭所有 TCP 转发
AllowTcpForwarding no
```

保存后

```bash
# 检查配置文件是否有语法错误
sudo sshd -t
```

重启SSH服务

```bash
# 重启SSH服务使配置生效
sudo systemctl restart ssh
# 或 sudo systemctl reload sshd 
```

## END
