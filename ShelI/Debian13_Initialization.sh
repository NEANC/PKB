#!/bin/bash
# SSH密钥初始化 + Debian13 更换源的初始化脚本
# 镜像优先级：中科大 > 阿里云 > 华为云
set -euo pipefail  # 严格错误处理

# ===================== 配置常量 =====================
SSH_DIR="$HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
SOURCE_FILE="/etc/apt/sources.list.d/debian.sources"

# ===================== 步骤1：SSH 密钥初始化 =====================
echo -e "\n========== 初始化 SSH 密钥 ==========\n"

# 创建 .ssh 目录并设置安全权限
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
echo "✅ 已创建目录：$SSH_DIR，权限 700"

# 创建授权密钥文件并设置安全权限
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"
echo "✅ 已创建文件：$AUTH_KEYS，权限 600"

# 读取用户公钥
echo -e "\n请粘贴你的 SSH 公钥（完整复制，以 ssh-ed25519 / ssh-rsa 开头）："
read -r SSH_PUB_KEY

# 校验公钥不能为空
if [[ -z "$SSH_PUB_KEY" ]]; then
    echo "❌ 错误：未输入公钥，脚本退出"
    exit 1
fi

# 写入公钥
echo "$SSH_PUB_KEY" > "$AUTH_KEYS"
echo -e "\n✅ SSH 公钥配置完成！"

# ===================== 步骤2：启用 Debian13 所有源码源 =====================
echo -e "\n========== 启用全部源码镜像源 ==========\n"

# 写入 DEB822 格式源（已启用所有 deb-src 源码，优先级：中科大 > 阿里云 > 华为云）
sudo tee "$SOURCE_FILE" > /dev/null <<-'EOF'
# Debian 13 (trixie) 国内镜像源 - DEB822 格式
# 主源、更新源、回退源（优先级：中科大 > 阿里云 > 华为云）
Types: deb
URIs: https://mirrors.ustc.edu.cn/debian
      https://mirrors.aliyun.com/debian
      https://repo.huaweicloud.com/debian
Suites: trixie trixie-updates trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 已启用：源码镜像
Types: deb-src
URIs: https://mirrors.ustc.edu.cn/debian
      https://mirrors.aliyun.com/debian
      https://repo.huaweicloud.com/debian
Suites: trixie trixie-updates trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 安全更新源
Types: deb
URIs: https://mirrors.ustc.edu.cn/debian-security
      https://mirrors.aliyun.com/debian-security
      https://repo.huaweicloud.com/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 已启用：安全更新源码镜像
Types: deb-src
URIs: https://mirrors.ustc.edu.cn/debian-security
      https://mirrors.aliyun.com/debian-security
      https://repo.huaweicloud.com/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

echo "✅ Debian 13 所有源码源（deb-src）已启用！"
echo "✅ 镜像优先级：中科大 > 阿里云 > 华为云"

# ===================== 步骤3：自动刷新软件包索引 =====================
echo -e "\n========== 自动刷新软件包索引 ==========\n"
echo "正在执行 sudo apt update..."
sudo apt update

# ===================== 步骤4：配置完成提示 =====================
echo -e "\n========== 全部配置完成！ ==========\n"
echo "🎉 SSH 密钥 + 国内源 + 源码源 配置已全部生效"
echo "✅ 软件包索引已自动刷新完成"
echo ""
echo "现在你可以直接使用 apt install 安装软件了！"