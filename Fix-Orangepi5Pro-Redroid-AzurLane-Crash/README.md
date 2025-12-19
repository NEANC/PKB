# Fix-Orangepi5Pro-Linux6.1-Redroid-AzurLane-Crash

修复 Orangepi5Pro 在官方 Linux6.1 内核镜像下，运行 Redroid 容器时碧蓝航线出现闪退的问题

---

## 介绍

> [!IMPORTANT]
> 关于为何需要使用 CNflysky/linux-rockchip 源码进行编译，请阅读 [discussions#16](https://github.com/CNflysky/redroid-rk3588/discussions/16)

预编译内核采用 [CNflysky/linux-rockchip](https://github.com/CNflysky/linux-rockchip) 进行编译，该源码集成了 dma-buf 驱动选项，专为 Redroid 适配。

> [!TIP]
> 该内核由 Alas-prod 群 微微黄 编译

测试镜像：Orangepi5pro_1.0.6_ubuntu_jammy_desktop_xfce_linux6.1.43  
预编译内核：6.1.84-rk3588-redroid

---

## 预编译内核安装步骤

1. 下载预编译内核和内核模块文件：

- [kernel.zip](https://github.com/NEANC/PKB/Fix-Orangepi5Pro-Linux6.1-Redroid-AzurLane-Crash/raw/refs/heads/main/kernel.zip)

2. 传输压缩包到设备：

```bash
scp X:\kernel.zip orangepi@192.168.X.X:/home/orangepi
```

3. 解压

```bash
unzip kernel.zip
```

4. 进入文件夹

```bash
cd kernel
```

5. 将 `6.1.84-rk3588-redroid` 文件夹复制到 `/lib/modules/`

```bash
sudo cp -r 6.1.84-rk3588-redroid /lib/modules/
```

6. 将 `ulnitrd` 与 `vmlinuz` 复制到 `/boot/`

```bash
sudo cp uInitrd-6.1.84-rk3588-redroid /boot/
sudo cp vmlinuz-6.1.84-rk3588-redroid /boot/
```

7.进入 boot 目录：

```bash
cd /boot
```

8. 备份并删除旧链接符号：

```bash
sudo cp Image Image-6.1.43-rockchip-rk3588
sudo cp uInitrd uInitrd-6.1.43-rockchip-rk3588
sudo rm -rf Image uInitrd
```

9. 使用复制方式应用内核：

```bash
sudo cp vmlinuz-6.1.84-rk3588-redroid Image
sudo cp uInitrd-6.1.84-rk3588-redroid uInitrd
```

> [!WARNING]  
> 为何不使用链接符号：
>
> ```bash
> orangepi@orangepi5pro:/boot$ sudo ln -s vmlinuz-6.1.84-rk3588-redroid Image
> ln: failed to create symbolic link 'Image': Operation not permitted
> orangepi@orangepi5pro:/boot$ sudo ln -s uInitrd-6.1.84-rk3588-redroid uInitrd
> ln: failed to create symbolic link 'uInitrd': Operation not permitted
> ```

10. 重启设备

```bash
sudo reboot
```

11. 使用预设脚本检测环境：

```bash
# 拉取脚本
wget https://raw.githubusercontent.com/CNflysky/redroid-rk3588/main/envcheck.sh
# 修改权限
chmod +x envcheck.sh
# 运行脚本
./envcheck.sh
```

12. 部署 docker 镜像，进行测试

> [!IMPORTANT]
> 若未安装 docker，可参考下方的安装步骤

下列为 3 个 redroid docker run 预设表

| 预设名称  | SOC 亲和性        |
| --------- | ----------------- |
| redroid-a | 4-5 大核          |
| redroid-b | 2-3 小核与 7 大核 |
| redroid-c | 0-1 小核与 6 大核 |

cpuset-cpus 参数用于绑定 CPU 核心，RK3588S 有 8 个核心，其中: Cortex-A55 小核是 0,1,2,3 ；Cortex-A76 大核是 4,5,6,7

---

### redroid-a

```bash
docker run -d \
  --name redroid-a \
  --privileged \
  -p 31000:5555 \
  -v /home/redroid/redroid-a-data:/data \
  --cpus="2.0" \
  --memory="4G" \
  --cpuset-cpus="4-5" \
  cnflysky/redroid-rk3588:lineage-20 \
  androidboot.redroid_width=1280 \
  androidboot.redroid_height=720 \
  androidboot.redroid_dpi=240 \
  androidboot.redroid_fps=60
```

---

### redroid-b

```bash
docker run -d \
  --name redroid-b \
  --privileged \
  -p 32000:5555 \
  -v /home/redroid/redroid-b-data:/data \
  --cpus="3.0" \
  --memory="4G" \
  --cpuset-cpus="2-3,7" \
  cnflysky/redroid-rk3588:lineage-20 \
  androidboot.redroid_width=1280 \
  androidboot.redroid_height=720 \
  androidboot.redroid_dpi=240 \
  androidboot.redroid_fps=60
```

---

### ### redroid-c

```bash
docker run -d \
  --name redroid-c \
  --privileged \
  -p 33000:5555 \
  -v /home/redroid/redroid-c-data:/data \
  --cpus="3.0" \
  --memory="4G" \
  --cpuset-cpus="0-1,6" \
  cnflysky/redroid-rk3588:lineage-20 \
  androidboot.redroid_width=1280 \
  androidboot.redroid_height=720 \
  androidboot.redroid_dpi=240 \
  androidboot.redroid_fps=60
```

---

## 安装 docker

1. 更新软件包索引并安装依赖

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
```

2. 添加 docker 的官方 GPG 密钥，并设置仓库

```bash
sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

3. 更新软件包索引并安装最新版 Docker 组件

```bash
sudo apt-get update

sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

4. 配置非 root 用户使用 Docker

```bash
# 添加 docker 组（通常安装时已自动创建）
sudo groupadd docker

# 将当前用户加入 docker 组
sudo usermod -aG docker $USER

# 重启会话生效（或重新登录）
newgrp docker
```

5.配置国内镜像加速：

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<EOF
{
    "registry-mirrors": [
        "https://docker.1ms.run",
        "https://hub.rat.dev",
        "https://hub.amingg.com"
    ]
}
EOF
```

6. 重启 Docker 生效

```bash
# 设置 Docker 开机自启
sudo systemctl enable docker
sudo systemctl daemon-reload
sudo systemctl restart docker
```

7. 测试 docker 是否安装成功

```bash
docker run hello-world
```

---

## 附录.修改源为中科大源

1.备份 `sources.list`

```bash
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
```

2.编辑源文件

```bash
sudo nano /etc/apt/sources.list

# 添加以下内容
deb https://mirrors.ustc.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
deb-src https://mirrors.ustc.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu-ports/ jammy-security main restricted universe multiverse
deb-src https://mirrors.ustc.edu.cn/ubuntu-ports/ jammy-security main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
deb-src https://mirrors.ustc.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse
deb-src https://mirrors.ustc.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse
```

3.更新软件包索引

```bash
sudo apt-get update
```

---
