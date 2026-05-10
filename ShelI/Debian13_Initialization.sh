#!/bin/bash
#==============================================================================
# Debian 13 初始化脚本：先换源刷新索引，后配置 SSH 密钥
# 特性：- 镜像优先级：中科大 > 阿里云 > 华为云
#       - DEB822 格式源配置
#       - 支持命令行传入 SSH 公钥
# 用法：
#   bash script.sh                        # 交互式输入公钥
#   bash script.sh -ssh "ssh-rsa AAA..."  # 通过参数传入公钥
#   curl ... | sudo bash -s -- -ssh "..." # 管道执行 + 参数
#==============================================================================
set -euo pipefail

# ---------------------------- 脚本目录 ----------------------------
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "bash" && "${BASH_SOURCE[0]}" != "-bash" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ "$0" != "bash" && "$0" != "-bash" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
else
    SCRIPT_DIR="$PWD"
fi

# ---------------------------- 日志文件 ----------------------------
LOGFILE="/tmp/debian_init.log"
touch "$LOGFILE" || { echo "无法创建日志文件 $LOGFILE"; exit 1; }
exec 3>>"$LOGFILE"
BASH_XTRACEFD=3
PS4='+$(date "+%H:%M:%S") | '
set -x

# ---------------------------- 加载图标 ----------------------------
ICON_OK="✔️"
ICON_WARN="⚠️"
ICON_ERROR="❌"

# ---------------------------- 颜色定义 ----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[37m'
NC='\033[0m'

# ---------------------------- 全局变量 ----------------------------
SSH_DIR="$HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
SOURCE_FILE="/etc/apt/sources.list.d/debian.sources"
_SPINNER_PID=""
SSH_PUB_KEY_FROM_CLI=""

# ---------------------------- 辅助函数 ----------------------------
echo_line() { echo -e "$1"; }

log_out() {
    local icon="$1"
    local color="$2"
    local msg="$3"
    echo_line "  ${icon} ${color}${msg}${NC}"
}
log_info() { log_out "" "${GREEN}" "$1"; }
log_ok()   { log_out "${ICON_OK}" "${GREEN}" "$1"; }
log_warn() { log_out "${ICON_WARN}" "${YELLOW}" "$1"; }
log_error(){ log_out "${ICON_ERROR}" "${RED}" "$1"; }

# 仅记录日志，不输出到终端
log_file() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOGFILE"
}

# ---------------------------- 流水灯系统 ----------------------------
_cleanup_spinner() {
    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null || true
        wait "$_SPINNER_PID" 2>/dev/null || true
        _SPINNER_PID=""
    fi
}

start_step() {
    _cleanup_spinner
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "$LOGFILE"
    local spin_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local idx=0
    {
        while true; do
            printf "\r${YELLOW}%s %s${NC}\033[K" "${spin_chars[$idx]}" "$msg"
            idx=$(( (idx + 1) % 10 ))
            sleep 0.15 2>/dev/null || true
        done
    } &
    _SPINNER_PID=$!
}

end_step() {
    local icon="$1"
    local msg="$2"
    local color="${3:-${GREEN}}"
    _cleanup_spinner
    printf "\r${icon} ${color}%s${NC}\033[K\n" "$msg"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${icon} ${msg}" >> "$LOGFILE"
}

# ---------------------------- 中断信号处理 ----------------------------
_sigint_handler() {
    _cleanup_spinner
    echo -e "\n  ${ICON_WARN} ${YELLOW}脚本已被用户中断${NC}"
    exit 130
}
trap '_sigint_handler' INT

# ---------------------------- 错误处理 ----------------------------
error_handler() {
    _cleanup_spinner
    local line_no=$1
    local error_code=$2
    echo_line "  ${ICON_ERROR} ${RED}脚本在第 ${line_no} 行发生错误 (错误码: ${error_code})${NC}"
    echo_line "  日志保存于: ${LOGFILE}"
    exit "${error_code}"
}
trap 'error_handler ${LINENO} $?' ERR

# ---------------------------- 打印标题 ----------------------------
print_header() {
    clear
    echo_line "${WHITE}"
    echo_line "  ____  _____ ____  _   _ ___ "
    echo_line " |  _ \| ____| __ )| \ | |_ _|"
    echo_line " | | | |  _| |  _ \|  \| || | "
    echo_line " | |_| | |___| |_) | |\  || | "
    echo_line " |____/|_____|____/|_| \_|___|"
    echo_line "${NC}"
    echo_line "  💻 Debian 13 初始化脚本：国内镜像源 + SSH 密钥"
    echo_line "  ─────────────────────────────────────────────────"
    echo_line "  ℹ️  镜像优先级：${BLUE}中科大${NC} > ${BLUE}阿里云${NC} > ${BLUE}华为云${NC}"
    echo_line "  ⚙️  源格式：${GREEN}DEB822${NC}"
    echo_line ""
}

# ---------------------------- 命令行参数解析 ----------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -ssh|--ssh-key)
                if [[ -z "${2:-}" ]]; then
                    echo_line "  ${ICON_ERROR} ${RED}错误：-ssh 参数需要一个公钥值${NC}"
                    exit 1
                fi
                SSH_PUB_KEY_FROM_CLI="$2"
                shift 2
                ;;
            *)
                echo_line "  ${ICON_WARN} ${YELLOW}未知参数: $1${NC}"
                shift
                ;;
        esac
    done
}

# ---------------------------- 第二步: 配置镜像源 ----------------------------
enable_sources() {
    start_step "正在配置 Debian 13 国内镜像源..."

    # 备份旧的源文件（如果存在）
    if [[ -f "$SOURCE_FILE" ]]; then
        local backup_file="${SOURCE_FILE}.bak.$(date +%Y%m%d%H%M%S)"
        if sudo cp "$SOURCE_FILE" "$backup_file"; then
            log_file "已备份旧的源文件到：${backup_file}"
        else
            log_file "备份旧源失败，将继续覆盖"
        fi
    fi

    start_step "正在配置 Debian 13 国内镜像源..."

    if ! sudo tee "$SOURCE_FILE" > /dev/null <<-'EOF'
# Debian 13 (trixie) 国内镜像源 - DEB822 格式
# 主源、更新源、回退源（优先级：中科大 > 阿里云 > 华为云）
Types: deb
URIs: https://mirrors.ustc.edu.cn/debian
      https://mirrors.aliyun.com/debian
      https://repo.huaweicloud.com/debian
Suites: trixie trixie-updates trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 源码镜像
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

# 安全更新源码镜像
Types: deb-src
URIs: https://mirrors.ustc.edu.cn/debian-security
      https://mirrors.aliyun.com/debian-security
      https://repo.huaweicloud.com/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    then
        end_step "${ICON_ERROR}" "镜像源配置失败" "${RED}"
        return 1
    fi

    log_file "已写入 ${SOURCE_FILE}"
    end_step "${ICON_OK}" "镜像源已配置（中科大 > 阿里云 > 华为云）"
}

# ---------------------------- 第三步: 刷新软件包索引 ----------------------------
refresh_index() {
    start_step "正在刷新软件包索引..."

    if ! sudo apt update >> "$LOGFILE" 2>&1; then
        end_step "${ICON_ERROR}" "软件包索引刷新失败，详情请阅读日志：${LOGFILE}" "${RED}"
        return 1
    fi

    end_step "${ICON_OK}" "软件包索引已刷新"
}

# ---------------------------- 第四步: SSH 密钥初始化（支持参数/交互/非交互） ----------------------------
init_ssh_keys() {
    start_step "准备 SSH 目录结构..."
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    touch "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    log_file "SSH 目录与授权文件就绪"
    end_step "${ICON_OK}" "SSH 目录已准备"

    local pubkey=""

    # 判断是否通过命令行提供了公钥
    if [[ -n "$SSH_PUB_KEY_FROM_CLI" ]]; then
        pubkey="$SSH_PUB_KEY_FROM_CLI"
        log_file "使用命令行提供的 SSH 公钥"
    else
        # 交互式读取：强制从 /dev/tty 获取输入（兼容管道执行）
        _cleanup_spinner
        echo_line ""
        echo_line "  🔑 ${CYAN}请粘贴你的 SSH 公钥${NC}"
        echo_line "  ${WHITE}（完整复制，以 ssh-ed25519 / ssh-rsa 开头）：${NC}"
        echo_line "  ─────────────────────────────────────────────────"
        echo -n "  > "

        # 直接从终端设备读取一行
        read -r pubkey < /dev/tty || true
        if [[ -z "$pubkey" ]]; then
            echo_line "  ${ICON_ERROR} ${RED}未输入公钥，脚本退出${NC}"
            exit 1
        fi

        # 格式校验：须以 ssh- 开头，且至少包含一个空格和后续内容
        if [[ ! "$pubkey" =~ ^ssh-(rsa|ed25519|ecdsa) ]] || \
           [[ "$pubkey" != *" "* ]]; then
            echo_line "  ${ICON_ERROR} ${RED}公钥格式无效！必须是一行完整公钥。${NC}"
            exit 1
        fi
        log_file "已从交互式输入读取公钥（通过 /dev/tty）"
    fi

    # 写入公钥
    start_step "正在写入 SSH 公钥..."
    echo "$pubkey" > "$AUTH_KEYS"
    log_file "公钥已写入 ${AUTH_KEYS}"
    end_step "${ICON_OK}" "SSH 密钥已配置"
}

# ---------------------------- 完成摘要 ----------------------------
print_completion() {
    echo_line ""
    echo_line "  🚀 ${GREEN}全部配置完成！${NC}"
    echo_line "  ℹ️  现在你可以直接使用 ${CYAN}apt install${NC} 安装软件了！"
    echo_line ""
}

# ---------------------------- 主流程 ----------------------------
main() {
    parse_args "$@"            # 解析命令行参数
    print_header
    enable_sources   || exit $?
    refresh_index    || exit $?
    init_ssh_keys
    print_completion
    rm -f "$LOGFILE"
}

main "$@"