#!/usr/bin/env bash
set -euo pipefail

# 在脚本目录执行只读检查，不运行部署或卸载操作。
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEPLOY="$SCRIPT_DIR/deploy-git-mirror.sh"
UNINSTALL="$SCRIPT_DIR/uninstall-git-mirror.sh"
FAILURES=0

# 检查指定文件包含预期的固定字符串。
assert_contains() {
    local file="$1" pattern="$2" description="$3"
    if grep -Fq -- "$pattern" "$file"; then
        printf '[PASS] %s\n' "$description"
    else
        printf '[FAIL] %s\n' "$description"
        printf '预期包含：%s\n' "$pattern"
        if [[ "$file" == *.log ]]; then
            while IFS= read -r actual_line || [ -n "$actual_line" ]; do
                printf '实际日志：%s\n' "$actual_line"
            done < "$file"
        fi
        FAILURES=$((FAILURES + 1))
    fi
    return 0
}

# 检查脚本不再包含被移除的配置或危险操作。
assert_absent() {
    local file="$1" pattern="$2" description="$3"
    if grep -Eiq -- "$pattern" "$file"; then
        printf '[FAIL] %s\n' "$description"
        FAILURES=$((FAILURES + 1))
    else
        printf '[PASS] %s\n' "$description"
    fi
    return 0
}

bash -n "$DEPLOY"
bash -n "$UNINSTALL"
printf '[PASS] 部署及卸载脚本 Bash 语法\n'
assert_absent "$DEPLOY" 'openresty|nginx|INTERNAL_PORT|EXTERNAL_PORT' '部署脚本移除反向代理及双端口配置'
assert_absent "$UNINSTALL" 'openresty|nginx|9419' '卸载脚本移除反向代理及内部端口配置'
assert_contains "$DEPLOY" '--listen=$LISTEN_ADDRESS' '服务使用明确的直连监听地址'
assert_contains "$DEPLOY" '--port=$GIT_PORT' '服务使用统一 Git 端口'
assert_contains "$DEPLOY" '--disable=receive-pack' '服务显式禁止推送'
assert_contains "$DEPLOY" 'Environment=HOME=/nonexistent' '只读 Git 服务不读取被隔离的用户主目录'
assert_contains "$DEPLOY" 'Environment=XDG_CONFIG_HOME=/nonexistent' '只读 Git 服务使用独立的配置查找路径'
assert_contains "$DEPLOY" 'ProtectHome=true' '保留服务主目录隔离保护'
assert_absent "$UNINSTALL" 'pkill -f|pkill -u|fuser -k' '卸载不批量终止其他服务进程'
assert_absent "$UNINSTALL" "sed -i '/github" '卸载不删除管理标记之外的 hosts 记录'

assert_contains "$UNINSTALL" 'if ! flock -n 9; then' '卸载前实际获取同步锁'
assert_contains "$UNINSTALL" 'exec 9<"$LOCK_FILE"' '卸载只读打开已有同步锁，兼容受保护的共享目录'
assert_absent "$UNINSTALL" 'exec 9>>' '卸载不以追加创建方式打开其他用户的锁文件'
assert_contains "$UNINSTALL" 'rm -f -- "$LOCK_FILE"' '卸载完成后删除同步锁文件'

assert_absent "$DEPLOY" '--strict-paths' '动态仓库目录不使用严格目录白名单模式'
assert_absent "$DEPLOY" 'access-hook|access\.mode|PATH_FUNCTIONS|build_flat_links|block-full-path|BLOCK_FULL_PATH' '部署脚本移除访问策略与自动短名链接'
assert_absent "$UNINSTALL" 'HOOK_SCRIPT|access-hook' '卸载脚本移除访问钩子清理'

# 拼接生成的同步脚本并检查整体语法，不执行同步或部署。
TEST_DIR=$(mktemp -d "$SCRIPT_DIR/.git-mirror-test.XXXXXX")
trap 'rm -rf -- "$TEST_DIR"' EXIT
awk "/^cat >>? .*<<'SYNC_SCRIPT_EOF'$/ { copying=1; blocks++; next } copying && /^SYNC_SCRIPT_EOF$/ { copying=0; next } copying { print } END { if (blocks != 2) exit 1 }" "$DEPLOY" > "$TEST_DIR/generated-sync.sh"
bash -n "$TEST_DIR/generated-sync.sh"
printf '[PASS] 拼接后的完整同步脚本 Bash 语法\n'

# 检查新增的部署入口和卸载路径记录。
assert_contains "$DEPLOY" '--repos-file' '支持逐行仓库及分支配置'
assert_contains "$DEPLOY" '--scripts-dir' '支持自定义脚本安装目录'
assert_contains "$DEPLOY" '--no-cron' '支持不配置定时任务'
assert_contains "$DEPLOY" 'select_connection_repo' '连接提示使用已发布仓库的完整路径'
assert_contains "$UNINSTALL" 'install.paths' '卸载读取实际脚本安装位置'

# 提取同步函数，使用本地裸仓库验证真实 refspec 行为。
awk '/^# 同步函数开始$/ { copying=1; next } /^# 同步函数结束$/ { copying=0 } copying { print }' "$DEPLOY" > "$TEST_DIR/sync-functions.sh"
if [ ! -s "$TEST_DIR/sync-functions.sh" ]; then
    printf '[FAIL] 缺少可独立验证的同步函数\n'
    FAILURES=$((FAILURES + 1))
else
    bash -n "$TEST_DIR/sync-functions.sh"
    source "$TEST_DIR/sync-functions.sh"

    # 对比实际结果与预期，不因单个断言失败而跳过其他检查。
    assert_equal() {
        local expected="$1" actual="$2" description="$3"
        if [ "$expected" = "$actual" ]; then
            printf '[PASS] %s\n' "$description"
        else
            printf '[FAIL] %s；预期：%s；实际：%s\n' "$description" "$expected" "$actual"
            FAILURES=$((FAILURES + 1))
        fi
        return 0
    }

    parse_repo_line 'LmeSzinc/AzurLaneAutoScript'
    assert_equal 'LmeSzinc/AzurLaneAutoScript|' "$REPO|$BRANCHES" '未指定分支时使用完整镜像'
    parse_repo_line 'git/git master'
    assert_equal 'git/git|master' "$REPO|$BRANCHES" '解析单分支'
    parse_repo_line 'torvalds/linux master,next,stable # 分支列表'
    assert_equal 'torvalds/linux|master,next,stable' "$REPO|$BRANCHES" '解析多分支和行尾注释'
    parse_repo_line $'git/git master\r'
    assert_equal 'git/git|master' "$REPO|$BRANCHES" '兼容 CRLF 仓库列表'
    for invalid in '../repo master' 'owner/repo master,,next' 'owner/repo master extra' 'owner/repo refs/*'; do
        if parse_repo_line "$invalid"; then
            printf '[FAIL] 应拒绝非法仓库配置：%s\n' "$invalid"
            FAILURES=$((FAILURES + 1))
        else
            printf '[PASS] 拒绝非法仓库配置：%s\n' "$invalid"
        fi
    done

    UPSTREAM="$TEST_DIR/upstream.git"
    MIRROR="$TEST_DIR/mirror.git"
    git init --bare --quiet "$UPSTREAM"
    TREE=$(git --git-dir="$UPSTREAM" mktree < /dev/null)
    COMMIT=$(git -c user.name=Fixture -c user.email=fixture@example.invalid --git-dir="$UPSTREAM" commit-tree "$TREE" -m fixture)
    for ref in refs/heads/master refs/heads/next refs/heads/stable refs/tags/v1 refs/notes/test; do
        git --git-dir="$UPSTREAM" update-ref "$ref" "$COMMIT"
    done
    git init --bare --quiet "$MIRROR"
    git --git-dir="$MIRROR" remote add origin "$UPSTREAM"

    configure_fetch "$MIRROR" ''
    git --git-dir="$MIRROR" fetch --quiet --prune origin
    assert_equal '+refs/*:refs/*' "$(git --git-dir="$MIRROR" config --get-all remote.origin.fetch)" '完整镜像使用全部 refs'
    assert_equal '5' "$(git --git-dir="$MIRROR" for-each-ref --format='%(refname)' | wc -l | tr -d ' ')" '完整镜像包含分支、标签和其他引用'

    configure_fetch "$MIRROR" 'master,next'
    git --git-dir="$MIRROR" fetch --quiet --prune origin
    prune_unselected_refs "$MIRROR" 'master,next'
    assert_equal $'refs/heads/master\nrefs/heads/next' "$(git --git-dir="$MIRROR" for-each-ref --format='%(refname)')" '缩小同步范围后仅保留所选分支'
    assert_equal '--no-tags' "$(git --git-dir="$MIRROR" config --get remote.origin.tagOpt)" '分支模式禁用标签自动获取'

    configure_fetch "$MIRROR" 'stable'
    git --git-dir="$MIRROR" fetch --quiet --prune origin
    prune_unselected_refs "$MIRROR" 'stable'
    assert_equal 'refs/heads/stable' "$(git --git-dir="$MIRROR" for-each-ref --format='%(refname)')" '可切换为单个分支'
    assert_equal 'refs/heads/stable' "$(git --git-dir="$MIRROR" symbolic-ref HEAD)" '默认分支指向所选首个分支'

    configure_fetch "$MIRROR" ''
    git --git-dir="$MIRROR" fetch --quiet --prune origin
    assert_equal '5' "$(git --git-dir="$MIRROR" for-each-ref --format='%(refname)' | wc -l | tr -d ' ')" '可从分支模式恢复完整镜像'
fi

# 提取分支报告函数，验证日志展示的是各分支自身的提交。
awk '/^# 分支报告开始$/ { copying=1; next } /^# 分支报告结束$/ { copying=0 } copying { print }' "$DEPLOY" > "$TEST_DIR/branch-report.sh"
if [ ! -s "$TEST_DIR/branch-report.sh" ]; then
    printf '[FAIL] 缺少逐分支提交报告函数\n'
    FAILURES=$((FAILURES + 1))
else
    bash -n "$TEST_DIR/branch-report.sh"
    source "$TEST_DIR/branch-report.sh"

    # 模拟日志出口，保留报告函数的实际 Git 查询行为。
    log() {
        printf '%s\n' "$*"
    }

    NEXT_COMMIT=$(GIT_AUTHOR_DATE='2026-01-02T03:04:05+08:00' GIT_COMMITTER_DATE='2026-01-02T03:04:05+08:00' git -c user.name=Fixture -c user.email=fixture@example.invalid --git-dir="$MIRROR" commit-tree "$TREE" -p "$COMMIT" -m 'next branch fixture')
    git --git-dir="$MIRROR" update-ref refs/heads/next "$NEXT_COMMIT"
    git --git-dir="$MIRROR" update-ref refs/heads/feature/report "$COMMIT"
    print_branch_commits fixture/repo "$MIRROR" '' success > "$TEST_DIR/report-all.log"
    SHORT_COMMIT=$(git --git-dir="$MIRROR" rev-parse --short=12 "$COMMIT")
    SHORT_NEXT=$(git --git-dir="$MIRROR" rev-parse --short=12 "$NEXT_COMMIT")
    assert_contains "$TEST_DIR/report-all.log" '本次同步成功' '成功报告明确同步状态'
    assert_contains "$TEST_DIR/report-all.log" "  ↳ master: $SHORT_COMMIT fixture" 'master 使用短哈希和简洁摘要'
    assert_contains "$TEST_DIR/report-all.log" "  ↳ next: $SHORT_NEXT next branch fixture" 'next 显示独立分支提交'
    assert_contains "$TEST_DIR/report-all.log" '    提交时间：2026-01-02T03:04:05+08:00' '提交时间单独缩进显示'
    assert_contains "$TEST_DIR/report-all.log" '  ↳ stable:' '完整镜像报告所有本地分支'
    assert_contains "$TEST_DIR/report-all.log" '  ↳ feature/report:' '分支名中的斜杠完整保留'
    assert_absent "$TEST_DIR/report-all.log" '↳ v1:|↳ test:' '报告不将标签和 notes 当成分支'
    assert_absent "$TEST_DIR/report-all.log" "$NEXT_COMMIT|分支：|摘要：|fixture/repo .*↳" '分支行不堆叠完整哈希、字段标签和仓库名'
    assert_equal '1' "$(grep -cF 'fixture/repo' "$TEST_DIR/report-all.log")" '仓库名称仅在报告标题出现一次'

    print_branch_commits fixture/repo "$MIRROR" 'next,master' success > "$TEST_DIR/report-selected.log"
    assert_contains "$TEST_DIR/report-selected.log" "  ↳ next: $SHORT_NEXT next branch fixture" '指定分支报告 next'
    assert_contains "$TEST_DIR/report-selected.log" "  ↳ master: $SHORT_COMMIT fixture" '指定分支报告 master'
    assert_absent "$TEST_DIR/report-selected.log" '↳ stable:|↳ feature/report:' '指定分支不展示范围外分支'

    print_branch_commits fixture/repo "$MIRROR" 'master,missing' failed > "$TEST_DIR/report-failed.log"
    assert_contains "$TEST_DIR/report-failed.log" '本次同步失败' '失败报告明确同步失败'
    assert_contains "$TEST_DIR/report-failed.log" '未确认上游最新' '失败时不将本地缓存误报为最新'
    assert_contains "$TEST_DIR/report-failed.log" '  ↳ missing: 本地不存在或无法读取提交' '缺失分支明确报告'
    assert_absent "$TEST_DIR/report-failed.log" '本次同步成功' '失败报告不出现成功状态'

    git init --bare --quiet "$TEST_DIR/empty.git"
    print_branch_commits fixture/empty "$TEST_DIR/empty.git" '' success > "$TEST_DIR/report-empty.log"
    assert_contains "$TEST_DIR/report-empty.log" '没有本地分支可报告' '空仓库明确报告且不中断执行'
fi
assert_absent "$DEPLOY" 'print_head_subject' '移除旧的仅 HEAD 报告'
assert_contains "$DEPLOY" 'print_branch_commits "$repo" "$dir" "$branches" success' '成功同步接入逐分支报告'
assert_contains "$DEPLOY" 'print_branch_commits "$repo" "$dir" "$branches" failed' '失败同步接入本地缓存报告'

# 验证 Git 同步不设置强制超时，并在非终端输出时保留原生进度。
assert_absent "$DEPLOY" 'FETCH_TIMEOUT|timeout "\$FETCH_TIMEOUT"|ConnectTimeout=' 'Git 调用不设置脚本级时间限制'
assert_contains "$DEPLOY" 'fetch --progress --atomic --prune origin' '拉取显式输出 Git 原生进度'

# 提取终端筛选函数；旧版本没有该函数时仍执行测试以复现失败。
awk '/^filter_fetch_output\(\) \{$/ { copying=1 } copying { print } copying && /^\}$/ { exit }' "$DEPLOY" > "$TEST_DIR/filter-output.sh"
source "$TEST_DIR/filter-output.sh"

# 提取命令执行函数，逐字节检查输出透传、日志追加和退出码。
awk '/^run_cmd\(\) \{$/ { copying=1 } copying { print } copying && /^\}$/ { exit }' "$DEPLOY" > "$TEST_DIR/run-command.sh"
if [ ! -s "$TEST_DIR/run-command.sh" ]; then
    printf '[FAIL] 未能提取命令执行函数\n'
    FAILURES=$((FAILURES + 1))
else
    source "$TEST_DIR/run-command.sh"
    LOG_FILE="$TEST_DIR/raw-command.log"
    printf 'existing log\n' > "$LOG_FILE"
    printf 'stdout message\nReceiving objects: 50%%\rReceiving objects: 100%%\n' > "$TEST_DIR/raw-expected.txt"
    command_status=0
    run_cmd bash -c 'printf "stdout message\n"; printf "Receiving objects: 50%%\rReceiving objects: 100%%\n" >&2; exit 7' > "$TEST_DIR/raw-actual.txt" || command_status=$?
    if cmp -s "$TEST_DIR/raw-expected.txt" "$TEST_DIR/raw-actual.txt" && [ "$command_status" -eq 7 ]; then
        printf '[PASS] 原始输出与回车进度完整保留，失败退出码正确\n'
    else
        printf '[FAIL] 原始输出或失败退出码发生变化\n'
        FAILURES=$((FAILURES + 1))
    fi
    { printf 'existing log\n'; cat "$TEST_DIR/raw-expected.txt"; } > "$TEST_DIR/log-expected.txt"
    if cmp -s "$TEST_DIR/log-expected.txt" "$LOG_FILE"; then
        printf '[PASS] 原始 Git 输出追加日志，不覆盖已有记录\n'
    else
        printf '[FAIL] 日志追加内容不匹配\n'
        FAILURES=$((FAILURES + 1))
    fi
fi

# 混合进度、正常引用和异常记录，验证只筛选终端展示。
{
    printf 'Receiving objects: 50%%\rReceiving objects: 100%%\r\n'
    printf '%s\n' 'From https://example.invalid/owner/repo'
    printf '%s\n' \
        ' * [new branch]      master -> master' \
        ' * [new tag]         v1 -> v1' \
        ' * [new ref]         refs/pull/1/head -> refs/pull/1/head' \
        '   abc1234..def5678   master -> master' \
        ' + abc1234...def5678  next -> next  (forced update)' \
        ' - [deleted]         (none) -> old' \
        ' = [up to date]      stable -> stable' \
        ' t [tag update]      v2 -> v2'
    printf '%s\n' \
        ' ! [rejected]        v3 -> v3 (would clobber existing tag)' \
        ' ! [remote rejected] next -> next (denied)' \
        'error: unable to update local ref' \
        'warning: example warning' \
        'fatal: example failure' \
        ' * [unknown status]  keep -> keep' \
        'remote: additional server message'
    printf 'Resolving deltas: 100%%\r\n'
    printf 'final message without newline'
} > "$TEST_DIR/fetch-input.txt"
{
    printf 'Receiving objects: 50%%\rReceiving objects: 100%%\r\n'
    printf '%s\n' \
        'From https://example.invalid/owner/repo' \
        ' ! [rejected]        v3 -> v3 (would clobber existing tag)' \
        ' ! [remote rejected] next -> next (denied)' \
        'error: unable to update local ref' \
        'warning: example warning' \
        'fatal: example failure' \
        ' * [unknown status]  keep -> keep' \
        'remote: additional server message'
    printf 'Resolving deltas: 100%%\r\n'
    printf 'final message without newline'
} > "$TEST_DIR/fetch-expected.txt"
LOG_FILE="$TEST_DIR/fetch-complete.log"
printf 'previous log\n' > "$LOG_FILE"
command_status=0
run_cmd bash -c 'cat "$1"; exit 7' _ "$TEST_DIR/fetch-input.txt" > "$TEST_DIR/fetch-terminal.txt" || command_status=$?
if cmp -s "$TEST_DIR/fetch-expected.txt" "$TEST_DIR/fetch-terminal.txt"; then
    printf '[PASS] 终端仅隐藏正常引用明细，保留进度、来源、异常和未知记录\n'
else
    printf '[FAIL] 终端引用明细筛选结果不正确\n'
    FAILURES=$((FAILURES + 1))
fi
{ printf 'previous log\n'; cat "$TEST_DIR/fetch-input.txt"; } > "$TEST_DIR/fetch-log-expected.txt"
if cmp -s "$TEST_DIR/fetch-log-expected.txt" "$LOG_FILE" && [ "$command_status" -eq 7 ]; then
    printf '[PASS] 完整日志逐字节追加，Git 失败退出码不被筛选覆盖\n'
else
    printf '[FAIL] 完整日志或 Git 退出码被改变\n'
    FAILURES=$((FAILURES + 1))
fi

# 提取连接提示函数，以模拟网卡验证地址选择，不修改网络配置。
awk '/^# IPv4 连接提示开始$/ { copying=1; next } /^# IPv4 连接提示结束$/ { copying=0 } copying { print }' "$DEPLOY" > "$TEST_DIR/connection-report.sh"
if [ ! -s "$TEST_DIR/connection-report.sh" ]; then
    printf '[FAIL] 缺少 IPv4 连接提示函数\n'
    FAILURES=$((FAILURES + 1))
else
    source "$TEST_DIR/connection-report.sh"
    # 仅替代网卡查询命令，输出函数仍使用实际实现。
    ip() {
        if [ "$*" != '-o -4 addr show up' ]; then
            return 1
        fi
        printf '%s\n' "$IP_FIXTURE"
        return 0
    }
    # 保留提示文本，便于检查完整命令。
    info() { printf '%s\n' "$*"; }
    # 保留警告文本，确认无地址时不会伪造命令。
    warn() { printf '%s\n' "$*"; }
    IP_FIXTURE=$'1: lo inet 127.0.0.1/8 scope host lo\n2: eth0 inet 192.168.10.5/24 scope global eth0\n3: eth1 inet 10.0.0.5/24 scope global eth1\n4: eth2 inet 192.168.10.5/24 scope global eth2\n5: eth3 inet 169.254.1.2/16 scope link eth3\n6: eth4 inet6 2001:db8::5/64 scope global'
    print_connection_commands 0.0.0.0 19418 Hello-World > "$TEST_DIR/connection-all.log"
    assert_contains "$TEST_DIR/connection-all.log" 'git ls-remote git://127.0.0.1:19418/Hello-World.git HEAD' '全接口监听使用回环地址本机验证'
    assert_contains "$TEST_DIR/connection-all.log" 'git clone git://192.168.10.5:19418/Hello-World.git' '客户端命令使用网卡 IPv4'
    assert_contains "$TEST_DIR/connection-all.log" 'git clone git://10.0.0.5:19418/Hello-World.git' '多网卡列出其他可用 IPv4'
    assert_equal '1' "$(grep -cF 'git clone git://192.168.10.5:' "$TEST_DIR/connection-all.log")" '重复 IPv4 只显示一次'
    assert_absent "$TEST_DIR/connection-all.log" 'git://0\.0\.0\.0|169\.254\.|2001:db8|<监听地址>|<域名>' '忽略不可用连接地址与 IPv6'

    print_connection_commands 10.0.0.5 19418 Hello-World > "$TEST_DIR/connection-bound.log"
    assert_contains "$TEST_DIR/connection-bound.log" 'git ls-remote git://10.0.0.5:19418/Hello-World.git HEAD' '指定 IPv4 使用实际监听地址验证'
    assert_absent "$TEST_DIR/connection-bound.log" 'git://127\.0\.0\.1|git://192\.168\.10\.5' '指定监听时不推荐其他网卡地址'

    print_connection_commands 127.0.0.1 19418 Hello-World > "$TEST_DIR/connection-loopback.log"
    assert_contains "$TEST_DIR/connection-loopback.log" '仅本机访问' '回环监听明确提示访问范围'
    assert_absent "$TEST_DIR/connection-loopback.log" 'git clone' '回环监听不打印远程克隆命令'

    IP_FIXTURE=''
    print_connection_commands 0.0.0.0 19418 Hello-World > "$TEST_DIR/connection-empty.log"
    assert_contains "$TEST_DIR/connection-empty.log" '未检测到' '缺少网卡地址时明确警告'
    assert_absent "$TEST_DIR/connection-empty.log" 'git clone' '无网卡 IPv4 时不伪造客户端地址'
    print_connection_commands 10.0.0.5 19418 Hello-World > "$TEST_DIR/connection-missing.log"
    assert_absent "$TEST_DIR/connection-missing.log" 'git clone' '指定 IPv4 未配置在网卡上时不推荐连接'
    print_connection_commands :: 19418 Hello-World > "$TEST_DIR/connection-ipv6.log"
    assert_absent "$TEST_DIR/connection-ipv6.log" 'git://' 'IPv6 监听不猜测 IPv4 可达性'
    unset -f ip info warn
fi
assert_absent "$DEPLOY" '<监听地址>|<域名>' '部署输出移除地址占位符'

# 提取连接提示中的仓库选择函数，验证只选已发布仓库且使用完整路径。
awk '/^# 选择首个已发布仓库用于部署后的连接提示/,/^}$/' "$DEPLOY" > "$TEST_DIR/select-repo.sh"
if [ ! -s "$TEST_DIR/select-repo.sh" ]; then
    printf '[FAIL] 缺少连接提示的仓库选择函数\n'
    FAILURES=$((FAILURES + 1))
else
    source "$TEST_DIR/select-repo.sh"
    SELECT_ROOT="$TEST_DIR/select-root"
    SELECT_LIST="$TEST_DIR/select-repos.list"
    mkdir -p "$SELECT_ROOT/alice"
    git init --bare --quiet "$SELECT_ROOT/alice/demo.git"
    printf 'alice/demo master\nalice/pending\n' > "$SELECT_LIST"
    assert_equal '' "$(select_connection_repo "$SELECT_ROOT" "$SELECT_LIST")" '未发布仓库不用于连接提示'
    touch "$SELECT_ROOT/alice/demo.git/git-daemon-export-ok"
    assert_equal 'alice/demo' "$(select_connection_repo "$SELECT_ROOT" "$SELECT_LIST")" '连接提示使用完整仓库路径'
    assert_equal '' "$(select_connection_repo "$SELECT_ROOT" "$TEST_DIR/missing.list")" '缺少仓库列表时返回空'
fi

printf '\n检查失败数：%s\n' "$FAILURES"
if [ "$FAILURES" -gt 0 ]; then
    exit 1
fi
