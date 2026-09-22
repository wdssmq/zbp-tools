#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="$SCRIPT_DIR/.env"

# 无交互模式标志
INTERACTIVE=true
TARGET_NAME=""
PLUGIN_NAME=""

error() {
	printf '错误：%s\n' "$*" >&2
}

usage() {
	cat <<EOF
用法：$0 [选项]

选项:
  -t, --target <name>   目标名称 (zbp17 或 zbp18)
  -p, --plugin <name>   插件名称
  -a, --all             同步所有插件
  -y, --yes             跳过确认提示
  -h, --help            显示此帮助信息

示例:
  $0 -t zbp17 -p myplugin          同步单个插件到指定目标
  $0 -t zbp18 -a -y                同步所有插件到 zbp18
  $0 --target zbp17 --plugin foo   同上 (使用长参数)
EOF
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || {
		error "未找到命令: $1"
		exit 1
	}
}

require_value() {
	local name=$1
	local value=$2
	[[ -n "$value" ]] || {
		error ".env 中的 $name 尚未设置。"
		return 1
	}
}

select_target() {
	local choice

	while true; do
		printf '\n选择目标:\n'
		printf '  1) zbp17\n'
		printf '  2) zbp18\n'
		printf '  0) 返回\n'
		read -r -p '选项: ' choice

		case "$choice" in
			1)
				TARGET_NAME=zbp17
				TARGET_WORKTREE=$ZBP17_WORKTREE
				TARGET_WEB_ROOT=$ZBP17_WEB_ROOT
				return 0
				;;
			2)
				TARGET_NAME=zbp18
				TARGET_WORKTREE=$ZBP18_WORKTREE
				TARGET_WEB_ROOT=$ZBP18_WEB_ROOT
				return 0
				;;
			0)
				return 1
				;;
			*)
				error '请输入 0、1 或 2。'
				;;
		esac
	done
}

collect_plugin_sources() {
	local plugin_dir="$TARGET_WORKTREE/zb_users/plugin"
	local entry src name

	PLUGINS=()
	PLUGIN_SRC_DIRS=()
	PLUGIN_NAMES=()

	# if [[ -d "$plugin_dir" ]]; then
	# 	while IFS= read -r -d '' entry; do
	# 		name=$(basename "$entry")
	# 		PLUGINS+=("$name")
	# 		PLUGIN_SRC_DIRS+=("$entry")
	# 		PLUGIN_NAMES+=("$name")
	# 	done < <(find "$plugin_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
	# fi

	for src_entry in "${ZBP_PLUGIN_SOURCES[@]+${ZBP_PLUGIN_SOURCES[@]}}"; do
		[[ -n "$src_entry" ]] || continue
		src=${src_entry%%:*}
		name=${src_entry#*:}
		[[ -n "$name" ]] || name=$(basename "$src")
		[[ -d "$src" ]] || continue
		PLUGINS+=("$name (外部)")
		PLUGIN_SRC_DIRS+=("$src")
		PLUGIN_NAMES+=("$name")
	done

	((${#PLUGINS[@]})) || {
		error "未找到任何插件源目录。"
		return 1
	}
}

select_plugin() {
	local choice

	collect_plugin_sources || return 1

	while true; do
		printf '\n选择要同步的插件:\n'
		local i=1
		for plugin in "${PLUGINS[@]}"; do
			printf '  %d) %s\n' "$i" "$plugin"
			((i++))
		done
		printf '  0) 返回\n'
		read -r -p '选项: ' choice

		[[ "$choice" == '0' ]] && return 1

		if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#PLUGINS[@]})); then
			PLUGIN_SRC_DIR="${PLUGIN_SRC_DIRS[$((choice - 1))]}"
			PLUGIN_NAME="${PLUGIN_NAMES[$((choice - 1))]}"
			return 0
		fi

		error "请输入 0 至 ${#PLUGINS[@]} 之间的数字。"
	done
}

sync_plugin() {
	local dest_dir="$TARGET_WEB_ROOT/zb_users/plugin/$PLUGIN_NAME"

	[[ -d "$PLUGIN_SRC_DIR" ]] || {
		error "插件源目录不存在: $PLUGIN_SRC_DIR"
		return 1
	}
	[[ -d "$TARGET_WEB_ROOT/zb_users/plugin" ]] || {
		error "目标插件目录不存在: $TARGET_WEB_ROOT/zb_users/plugin"
		return 1
	}

	printf '\n将使用 rsync 同步插件 %s 到 %s\n' "$PLUGIN_NAME" "$dest_dir"
	read -r -p '确认继续？输入 yes: ' answer
	[[ "$answer" == 'yes' ]] || {
		printf '已取消。\n'
		return 0
	}

	mkdir -p "$dest_dir"
	rsync -av --delete \
		--exclude='.git' \
		--exclude='.gitignore' \
		--exclude='.editorconfig' \
		"$PLUGIN_SRC_DIR/" "$dest_dir/"

	printf '同步完成: %s\n' "$dest_dir"
}

parse_args() {
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
			-a|--all)
				ALL_PLUGINS=true
				shift
				;;
			-y|--yes)
				INTERACTIVE=false
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

	# 验证参数
	if [[ -n "$TARGET_NAME" ]]; then
		[[ "$TARGET_NAME" == "zbp17" || "$TARGET_NAME" == "zbp18" ]] || {
			error "目标必须是 zbp17 或 zbp18"
			exit 1
		}
	else
		error "必须指定目标 (-t/--target)"
		exit 1
	fi

	if [[ -z "$PLUGIN_NAME" && -z "$ALL_PLUGINS" ]]; then
		error "必须指定插件 (-p/--plugin) 或使用 -a 同步所有"
		exit 1
	fi
}

run_non_interactive() {
	local dest_dir="$TARGET_WEB_ROOT/zb_users/plugin/$PLUGIN_NAME"

	[[ -d "$PLUGIN_SRC_DIR" ]] || {
		error "插件源目录不存在：$PLUGIN_SRC_DIR"
		return 1
	}
	[[ -d "$TARGET_WEB_ROOT/zb_users/plugin" ]] || {
		error "目标插件目录不存在：$TARGET_WEB_ROOT/zb_users/plugin"
		return 1
	}

	printf '将使用 rsync 同步插件 %s 到 %s\n' "$PLUGIN_NAME" "$dest_dir"

	mkdir -p "$dest_dir"
	rsync -av --delete \
		--exclude='.git' \
		--exclude='.gitignore' \
		--exclude='.editorconfig' \
		"$PLUGIN_SRC_DIR/" "$dest_dir/"

	printf '同步完成：%s\n' "$dest_dir"
}

main() {
	[[ -f "$ENV_FILE" ]] || {
		error "未找到配置文件：$ENV_FILE"
		exit 1
	}
	# shellcheck disable=SC1090
	source "$ENV_FILE"

	require_command rsync

	parse_args "$@"

	trap 'printf "\n已退出。\n"; exit 130' INT

	# 无交互模式
	if [[ "$INTERACTIVE" == "false" ]]; then
		# 设置目标
		case "$TARGET_NAME" in
			zbp17)
				TARGET_WORKTREE=$ZBP17_WORKTREE
				TARGET_WEB_ROOT=$ZBP17_WEB_ROOT
				;;
			zbp18)
				TARGET_WORKTREE=$ZBP18_WORKTREE
				TARGET_WEB_ROOT=$ZBP18_WEB_ROOT
				;;
		esac

		# 收集插件源
		collect_plugin_sources || exit 1

		if [[ -n "$PLUGIN_NAME" ]]; then
			# 同步指定插件
			local found=false
			for i in "${!PLUGIN_NAMES[@]}"; do
				if [[ "${PLUGIN_NAMES[$i]}" == "$PLUGIN_NAME" ]]; then
					PLUGIN_SRC_DIR="${PLUGIN_SRC_DIRS[$i]}"
					PLUGIN_NAME="${PLUGIN_NAMES[$i]}"
					found=true
					break
				fi
			done
			[[ "$found" == "true" ]] || {
				error "未找到插件：$PLUGIN_NAME"
				exit 1
			}
			run_non_interactive
		elif [[ "${ALL_PLUGINS:-}" == "true" ]]; then
			# 同步所有插件
			for i in "${!PLUGIN_NAMES[@]}"; do
				PLUGIN_SRC_DIR="${PLUGIN_SRC_DIRS[$i]}"
				PLUGIN_NAME="${PLUGIN_NAMES[$i]}"
				run_non_interactive
			done
		fi
	else
		# 交互模式
		select_target || return 0
		select_plugin || return 0
		sync_plugin
	fi
}

main "$@"
