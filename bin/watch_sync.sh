#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="$SCRIPT_DIR/.env"

# 错误处理
error() {
	printf '错误：%s\n' "$*" >&2
}

# 检查依赖
require_command() {
	command -v "$1" >/dev/null 2>&1 || {
		error "未找到命令：$1"
		exit 1
	}
}

# 加载配置
[[ -f "$ENV_FILE" ]] || {
	error "未找到配置文件：$ENV_FILE"
	exit 1
}
# shellcheck disable=SC1090
source "$ENV_FILE"

# 检查必需命令
require_command watchexec
require_command rsync

# 显示用法
usage() {
	cat <<EOF
用法：$0 [选项]

选项:
  -t, --target <name>     目标名称 (zbp17 或 zbp18)，覆盖 .env 配置
  -p, --plugin <name>     插件名称，覆盖 .env 配置
  -w, --watch-all         监控所有配置的插件源
  -h, --help              显示此帮助信息

环境变量 (.env):
  ZBP_WATCH_TARGET        默认目标 (zbp17 或 zbp18)
  ZBP_WATCH_PLUGIN        默认插件名称

示例:
  $0                              # 使用 .env 配置
  $0 -t zbp18 -p UEditor          # 监控 UEditor 到 zbp18
  $0 -w                           # 监控所有配置的插件源
EOF
}

# 解析参数
TARGET_NAME="${ZBP_WATCH_TARGET:-}"
PLUGIN_NAME="${ZBP_WATCH_PLUGIN:-}"
WATCH_ALL=false

while [[ $# -gt 0 ]]; do
	case "$1" in
		-t|--target)
			TARGET_NAME="$2"
			shift 2
			;;
		-p|--plugin)
			PLUGIN_NAME="$2"
			shift 2
			;;
		-w|--watch-all)
			WATCH_ALL=true
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			error "未知参数：$1"
			usage
			exit 1
			;;
	esac
done

# 验证目标
if [[ -z "$TARGET_NAME" ]]; then
	error "必须指定目标 (-t/--target) 或在 .env 中设置 ZBP_WATCH_TARGET"
	exit 1
fi

[[ "$TARGET_NAME" == "zbp17" || "$TARGET_NAME" == "zbp18" ]] || {
	error "目标必须是 zbp17 或 zbp18"
	exit 1
}

# 设置目标路径
case "$TARGET_NAME" in
	zbp17)
		TARGET_WEB_ROOT=$ZBP17_WEB_ROOT
		;;
	zbp18)
		TARGET_WEB_ROOT=$ZBP18_WEB_ROOT
		;;
esac

# 收集插件源
collect_plugin_sources() {
	local plugin_dir="$TARGET_WEB_ROOT/zb_users/plugin"
	local entry src name

	PLUGINS=()
	PLUGIN_SRC_DIRS=()
	PLUGIN_NAMES=()

	# 从 .env 收集插件源
	for src_entry in "${ZBP_PLUGIN_SOURCES[@]+${ZBP_PLUGIN_SOURCES[@]}}"; do
		[[ -n "$src_entry" ]] || continue
		src=${src_entry%%:*}
		name=${src_entry#*:}
		[[ -n "$name" ]] || name=$(basename "$src")
		[[ -d "$src" ]] || continue
		PLUGINS+=("$name")
		PLUGIN_SRC_DIRS+=("$src")
		PLUGIN_NAMES+=("$name")
	done
}

# 同步单个插件
sync_plugin() {
	local src_dir="$1"
	local name="$2"
	local dest_dir="$TARGET_WEB_ROOT/zb_users/plugin/$name"

	printf '\n[%s] 同步插件：%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$name"
	printf '  源：%s\n' "$src_dir"
	printf '  目标：%s\n' "$dest_dir"

	mkdir -p "$dest_dir"
	if rsync -av --delete \
		--exclude='.git' \
		--exclude='.gitignore' \
		--exclude='.editorconfig' \
		--exclude='.DS_Store' \
		"$src_dir/" "$dest_dir/"; then
		printf '  ✓ 同步成功\n'
	else
		printf '  ✗ 同步失败\n'
		return 1
	fi
}

# 主监控函数
run_watch() {
	local watch_path="$1"
	local plugin_name="$2"

	printf '\n========================================\n'
	printf '开始监控：%s\n' "$watch_path"
	printf '同步到：%s/zb_users/plugin/%s\n' "$TARGET_WEB_ROOT" "$plugin_name"
	printf '========================================\n\n'

  watchexec \
    --wrap-process=session \
    --shell none \
    --watch "$watch_path" \
    --ignore '.git' \
    --ignore '.history' \
    -- \
    bash -c './sync.sh -t "$0" -p "$1" -y' "$TARGET_NAME" "$plugin_name"
}

# 启动监控
if [[ "$WATCH_ALL" == "true" ]]; then
	# 监控所有插件源
	collect_plugin_sources || exit 1

	if ((${#PLUGIN_NAMES[@]} == 0)); then
		error "未找到任何插件源目录"
		exit 1
	fi

	printf '监控 %d 个插件源:\n' "${#PLUGIN_NAMES[@]}"
	for i in "${!PLUGIN_NAMES[@]}"; do
		printf '  • %s -> %s\n' "${PLUGIN_NAMES[$i]}" "${PLUGIN_SRC_DIRS[$i]}"
	done
	printf '\n按 Ctrl+C 停止监控\n\n'

	# 并发监控所有插件源
	for i in "${!PLUGIN_NAMES[@]}"; do
		( run_watch "${PLUGIN_SRC_DIRS[$i]}" "${PLUGIN_NAMES[$i]}" ) &
	done

	# 等待所有后台进程
	wait
else
	# 从插件源列表中选择
	collect_plugin_sources || exit 1

	if [[ -z "$PLUGIN_NAME" ]]; then
		error "必须指定插件名称 (-p/--plugin) 或使用 -w 监控所有"
		exit 1
	fi

	# 查找插件源目录
	found=false
	watch_dir=""
	for i in "${!PLUGIN_NAMES[@]}"; do
		if [[ "${PLUGIN_NAMES[$i]}" == "$PLUGIN_NAME" ]]; then
			watch_dir="${PLUGIN_SRC_DIRS[$i]}"
			found=true
			break
		fi
	done

	[[ "$found" == "true" ]] || {
		error "未找到插件：$PLUGIN_NAME"
		exit 1
	}

	run_watch "$watch_dir" "$PLUGIN_NAME"
fi
