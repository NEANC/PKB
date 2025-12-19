# GitProxy - Windows 设置

> [!NOTE]
> 本文仅限在 Windows 系统中使用，其他系统请查阅官方文档
>
> > 请 **`打开代理软件`** 并 **`关闭杀毒软件后`** 再进行设置

## Git 全局设置

在 `Git Bash(以管理员身份运行)` 中执行下列任意命令：

- 仅需要设置一个代理 `Http` 或 `Socks5`

  - 请将 `<port>` 修改为 代理端口

- 设置 **`Http 全局代理`**

```Shell
    git config –-global http.proxy http://127.0.0.1:<port>
```

- 设置 **`Socks5 全局代理`**

```Shell
    git config --global http.proxy socks5://127.0.0.1:<port>
```

### 验证设置

验证全局设置，请在 `Git Bash` 中执行下列命令

```Shell
    git config --global -e
```

随后按 `ESC 键` 进入 `VIM 命令模式`，输入 `:q` 退出

## 当 Git 使用 SSH 传输时，使用代理进行链接

- **`SSH 传输`** 不通过全局设置进行链接，需要额外设置
- 请提前配置 **`SSH 密钥`**
  - 当然也可以在设置代理后再部署

在 `Git Bash(以管理员身份运行)` 中使用 `vim` 进入 `~/.ssh/config` 进行配置

- 仅需要设置一个代理 `Http` 或 `Socks5`
  - 请将 `<port>` 修改为 代理端口

```Shell
    vim ~/.ssh/config
```

- 设置 **`Http 代理`** `github.com`，复制粘贴以下内容

```Shell
    Host github.com
    Hostname ssh.github.com
    Port 443
    User git
    ProxyCommand connect -H 127.0.0.1:<port> %h %p
```

- 设置 **`Socks5 代理`** `github.com`，复制粘贴以下内容

```Shell
    Host github.com
    Hostname ssh.github.com
    Port 443
    User git
    ProxyCommand connect -S 127.0.0.1:<port> %h %p
```

随后按 `ESC 键` 进入 `VIM 命令模式`，输入 `:wq` 保存退出

- 可使用 `:qa!` 强制保存退出

### 验证 SSH 代理设置

```Shell
    ssh -T git@github.com
```

- **如出现类似下列报告说明配置成功**

  - 若您已配置`SSH 密钥`

    ```Shell
    > The authenticity of host '[ssh.github.com]:443 ([140.82.112.36]:443)' can't be established.
    > ED25519 key fingerprint is SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU.
    > This host key is known by the following other names/addresses:
    >     ~/.ssh/known_hosts:32: github.com
    > Are you sure you want to continue connecting (yes/no/[fingerprint])?
    ```

  - 若您未配置 `SSH 密钥`

    ```Shell
    > The authenticity of host '[ssh.github.com]:443 ([20.205.243.160]:443)' can't be established.
    > ED25519 key fingerprint is SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU.
    > This key is not known by any other names.
    > Are you sure you want to continue connecting (yes/no/[fingerprint])?
    ```

> [!CAUTION] > **折叠的内容会导致设置繁琐，不建议查阅，请勿使用**！
>
> > 原因：若代理服务器未打开 22 端口，会导致:**`Connection closed by UNKNOWN port 65535`**错误!
> >
> > > 解决方案：[在 HTTPS 端口使用 SSH](https://docs.github.com/zh/authentication/troubleshooting-ssh/using-ssh-over-the-https-port "Github 文档")

<details>
<summary>
以下为存档内容，不建议查阅
</summary>

## 当 Git 使用 SSH 传输时，使用代理进行链接

- **`SSH 传输`** 不通过全局设置进行链接，需要额外设置
- 请提前配置 **`SSH 密钥`**
  - 当然也可以在设置代理后再部署

在 `Git Bash(以管理员身份运行)` 中使用 `vim` 进入 `~/.ssh/config` 进行配置

- 仅需要设置一个代理 `Http` 或 `Socks5`
  - 请将 <port> 修改为 代理端口

```Shell
    vim ~/.ssh/config
```

- 设置 **`Http 代理`** `github.com`，复制粘贴以下内容

```Shell
    Host github.com
    User git
    ProxyCommand connect -H 127.0.0.1:<port> %h %p
```

- 设置 **`Socks5 代理`** `github.com`，复制粘贴以下内容

```Shell
    Host github.com
    User git
    ProxyCommand connect -S 127.0.0.1:<port> %h %p
```

随后按 `ESC 键` 进入 `VIM 命令模式`，输入 `:wq` 保存退出

### 验证 SSH 代理设置

```Shell
    ssh -T git@github.com
```

#### 解决错误

> [!WARNING]
> 如运行`ssh -T git@github.com`后报告下列错误，请继续阅读本文。
>
> > 若不是下列的错误代码，请在 **搜索引擎** 中对 **Git 错误代码** 进行搜索来寻求解决方案。

```Shell
    Connection closed by UNKNOWN port 65535
```

##### 解决方案

- [在 HTTPS 端口使用 SSH](https://docs.github.com/zh/authentication/troubleshooting-ssh/using-ssh-over-the-https-port "Github 文档")

1. 在 `Git Bash(以管理员身份运行)` 中使用 `vim` 进入 `~/.ssh/config` 进行配置

   - 按 `ESC 键` 进入 `VIM 命令模式`，输入 `:i` 进入编辑模式
   - **需要编辑的内容已在下方高亮**

   ```diff
   Host github.com
   + Hostname ssh.github.com
   + Port 443
   User git
   ```

2. 按 `ESC 键` 进入 `VIM 命令模式`，输入 `:wq` 保存退出

   - 在退出前，**请确认 `Http 代理`完整代码为**

   ```Shell
    Host github.com
    Hostname ssh.github.com
    Port 443
    User git
    ProxyCommand connect -H 127.0.0.1:<port> %h %p
   ```

   - 在退出前，**请确认 `Socks5 代理`完整代码为**

   ```Shell
    Host github.com
    Hostname ssh.github.com
    Port 443
    User git
    ProxyCommand connect -S 127.0.0.1:<port> %h %p
   ```

3. 退出后再次运行`ssh -T git@github.com`

   - **如出现类似下列报告说明配置成功**
   - 若您已配置`SSH 密钥`

   ```Shell
   > The authenticity of host '[ssh.github.com]:443 ([140.82.112.36]:443)' can't be established.
   > ED25519 key fingerprint is SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU.
   > This host key is known by the following other names/addresses:
   >     ~/.ssh/known_hosts:32: github.com
   > Are you sure you want to continue connecting (yes/no/[fingerprint])?
   ```

   - 若您未配置 `SSH 密钥`

   ```Shell
   > The authenticity of host '[ssh.github.com]:443 ([20.205.243.160]:443)' can't be established.
   > ED25519 key fingerprint is SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU.
   > This key is not known by any other names.
   > Are you sure you want to continue connecting (yes/no/[fingerprint])?
   ```

</details>

### 参考文档

[Eric's Blog](https://ericclose.github.io/git-proxy-config.html "一文让你了解如何为 Git 设置代理")  
[Hex Blog](https://bannirui.github.io/2024/01/24/%E4%BB%A3%E7%90%86git%E7%9A%84ssh%E5%8D%8F%E8%AE%AE/ "代理git的ssh协议")  
[在 HTTPS 端口使用 SSH](https://docs.github.com/zh/authentication/troubleshooting-ssh/using-ssh-over-the-https-port)  
[基本撰写和格式语法](https://docs.github.com/zh/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)  
[创建和突显代码块](https://docs.github.com/zh/get-started/writing-on-github/working-with-advanced-formatting/creating-and-highlighting-code-blocks)  
[使用折叠部分组织信息](https://docs.github.com/zh/get-started/writing-on-github/working-with-advanced-formatting/organizing-information-with-collapsed-sections)
