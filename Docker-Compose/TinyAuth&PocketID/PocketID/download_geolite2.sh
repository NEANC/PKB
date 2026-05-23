#!/bin/bash

# PocketID GeoLite2 数据库下载脚本
# 脚本会下载 GeoLite2-City.mmdb 数据库文件到 ./data 目录下
# 使用说明：
# 1. 进入PocketID文件夹：cd PocketID
# 2. 下载脚本：wget https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/PocketID/download_geolite2.sh
# 3. 赋予执行权限：chmod +x download_geolite2.sh
# 4. 运行脚本：bash download_geolite2.sh ；脚本会自动下载 GeoLite2-City.mmdb 文件到 ./data/ 目录下
# 5. 使用 1Panel 设置计划任务

# 自动获取脚本所在目录
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# 目标文件夹：自动拼接 pocket-id/data
TARGET_DIR="${SCRIPT_DIR}/data"
TARGET_FILE="${TARGET_DIR}/GeoLite2-City.mmdb"

# 下载地址
PRIMARY_URL="https://ghfast.top/github.com/P3TERX/GeoLite.mmdb/releases/latest/download/GeoLite2-City.mmdb"
BACKUP_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"

# docker 容器名
DOCKER_SERVICE="pocket-id"

# 日志函数，输出带时间戳的日志
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 定位目录与文件
mkdir -p "${TARGET_DIR}"
log "脚本目录：${SCRIPT_DIR}"
log "目标文件：${TARGET_FILE}"

# 下载函数，尝试下载并验证文件
download() {
    local url="$1"
    log "开始下载：$url"
    # wget静默下载，先保存为临时文件
    wget -q --timeout=60 --tries=3 -O "${TARGET_FILE}.tmp" "$url"

    if [ $? -eq 0 ] && [ -s "${TARGET_FILE}.tmp" ]; then
        mv -f "${TARGET_FILE}.tmp" "${TARGET_FILE}"
        return 0
    else
        rm -f "${TARGET_FILE}.tmp"
        return 1
    fi
}

# 尝试使用主链接下载，失败则尝试备用链接
if download "${PRIMARY_URL}"; then
    log "✅ 主链接下载完成"
elif download "${BACKUP_URL}"; then
    log "✅ 备用链接下载完成"
else
    log "❌ 所有链接下载失败"
    exit 1
fi

# 重启容器
log "🔄 开始重启 ${DOCKER_SERVICE} 容器"
cd "${SCRIPT_DIR}" && docker compose restart "${DOCKER_SERVICE}"

if [ $? -eq 0 ]; then
    log "✅ 容器重启成功！任务全部完成"
else
    log "⚠️ 容器重启失败，请手动检查docker状态"
    exit 1
fi