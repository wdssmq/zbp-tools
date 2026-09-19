#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="$SCRIPT_DIR/.env"

error() {
	printf '错误: %s\n' "$*" >&2
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || {
		error "未找到命令: $1"
		exit 1
	}
}

confirm() {
	local answer
	read -r -p '确认继续？输入 yes: ' answer
	[[ "$answer" == 'yes' ]]
}

require_value() {
	local name=$1
	local value=$2
	[[ -n "$value" ]] || {
		error ".env 中的 $name 尚未设置。"
		return 1
	}
}

ensure_admin_password() {
	[[ -n "$ZBP_ADMIN_PASSWORD" ]] && return 0

	read -r -s -p '管理员密码: ' ZBP_ADMIN_PASSWORD
	printf '\n'
	[[ -n "$ZBP_ADMIN_PASSWORD" ]] || {
		error '管理员密码不能为空。'
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

check_target() {
	[[ -d "$TARGET_WEB_ROOT" ]] || {
		error "部署目录不存在: $TARGET_WEB_ROOT"
		return 1
	}
	[[ -f "$TARGET_WEB_ROOT/zb_install/cli.php" ]] || {
		error "未找到 CLI 安装器: $TARGET_WEB_ROOT/zb_install/cli.php"
		return 1
	}
}

deploy() {
	local version archive utils_dir_created=false

	select_target || return 0
	[[ -d "$TARGET_WORKTREE/.git" ]] || {
		error "Git 工作树不存在或不是仓库: $TARGET_WORKTREE"
		return 1
	}
	[[ -d "$TARGET_WEB_ROOT" ]] || {
		error "部署目录不存在: $TARGET_WEB_ROOT"
		return 1
	}
	[[ -f "$TARGET_WORKTREE/utils/get_version.php" ]] || {
		error "未找到版本脚本: $TARGET_WORKTREE/utils/get_version.php"
		return 1
	}
	[[ -f "$TARGET_WORKTREE/utils/put_appcentre.php" ]] || {
		error "未找到 AppCentre 脚本: $TARGET_WORKTREE/utils/put_appcentre.php"
		return 1
	}

	version=$(cd "$TARGET_WORKTREE" && php utils/get_version.php --short)
	archive="$ZBP_ARCHIVE_DIR/zblogphp-${version}.zip"

	printf '\n将从 %s 打包版本 %s，并清空 %s。\n' "$TARGET_WORKTREE" "$version" "$TARGET_WEB_ROOT"
	confirm || {
		printf '已取消。\n'
		return 0
	}

	mkdir -p "$ZBP_ARCHIVE_DIR"
	rm -f -- "$archive"
	(cd "$TARGET_WORKTREE" && git archive -o "$archive" HEAD)
	find "$TARGET_WEB_ROOT" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
	unzip -q "$archive" -d "$TARGET_WEB_ROOT"
	cp "$TARGET_WORKTREE/.gitignore" "$TARGET_WORKTREE/.editorconfig" "$TARGET_WEB_ROOT/"
	if [[ ! -d "$TARGET_WEB_ROOT/utils" ]]; then
		mkdir -p "$TARGET_WEB_ROOT/utils"
		utils_dir_created=true
	fi
	cp "$TARGET_WORKTREE/utils/put_appcentre.php" "$TARGET_WEB_ROOT/utils/"
	if ! (
		cd "$TARGET_WEB_ROOT"
		php utils/put_appcentre.php
	); then
		rm -f -- "$TARGET_WEB_ROOT/utils/put_appcentre.php"
		[[ "$utils_dir_created" == true ]] && rmdir -- "$TARGET_WEB_ROOT/utils"
		return 1
	fi
	rm -f -- "$TARGET_WEB_ROOT/utils/put_appcentre.php"
	[[ "$utils_dir_created" == true ]] && rmdir -- "$TARGET_WEB_ROOT/utils"

	printf '部署完成: %s\n归档文件: %s\n' "$TARGET_WEB_ROOT" "$archive"
}

install_sqlite() {
	select_target || return 0
	check_target || return 1

	printf '\n将在 %s 使用 SQLite 重新安装站点“%s”。\n' "$TARGET_WEB_ROOT" "$ZBP_SITE_NAME"
	confirm || {
		printf '已取消。\n'
		return 0
	}
	ensure_admin_password || return 1

	(
		cd "$TARGET_WEB_ROOT"
		ZBP_ADMIN_PASSWORD="$ZBP_ADMIN_PASSWORD" php zb_install/cli.php \
			--db-type=sqlite3 \
			--site-name="$ZBP_SITE_NAME" \
			--admin-user="$ZBP_ADMIN_USER"
	)
}

install_mysql() {
	select_target || return 0
	check_target || return 1
	require_value ZBP_MYSQL_DATABASE "$ZBP_MYSQL_DATABASE" || return 1
	require_value ZBP_MYSQL_USER "$ZBP_MYSQL_USER" || return 1
	require_value ZBP_MYSQL_PASSWORD "$ZBP_MYSQL_PASSWORD" || return 1

	printf '\n将在 %s 使用 MySQL 数据库“%s”重新安装站点“%s”。\n' "$TARGET_WEB_ROOT" "$ZBP_MYSQL_DATABASE" "$ZBP_SITE_NAME"
	confirm || {
		printf '已取消。\n'
		return 0
	}
	ensure_admin_password || return 1

	(
		cd "$TARGET_WEB_ROOT"
		ZBP_ADMIN_PASSWORD="$ZBP_ADMIN_PASSWORD" ZBP_DB_PASSWORD="$ZBP_MYSQL_PASSWORD" php zb_install/cli.php \
			--db-type="$ZBP_MYSQL_TYPE" \
			--db-server="$ZBP_MYSQL_SERVER" \
			--db-port="$ZBP_MYSQL_PORT" \
			--db-name="$ZBP_MYSQL_DATABASE" \
			--db-user="$ZBP_MYSQL_USER" \
			--db-prefix="$ZBP_MYSQL_PREFIX" \
			--db-engine="$ZBP_MYSQL_ENGINE" \
			--site-name="$ZBP_SITE_NAME" \
			--admin-user="$ZBP_ADMIN_USER"
	)
}

main() {
	local choice

	[[ -f "$ENV_FILE" ]] || {
		error "未找到配置文件: $ENV_FILE"
		exit 1
	}
	# shellcheck disable=SC1090
	source "$ENV_FILE"

	require_command php
	require_command git
	require_command unzip
	require_command find

	trap 'printf "\n已退出。\n"; exit 130' INT

	while true; do
		printf '\nZ-BlogPHP 管理脚本\n'
		printf '  1) 本地打包并部署\n'
		printf '  2) CLI 安装 SQLite\n'
		printf '  3) CLI 安装 MySQL\n'
		printf '  0) 退出\n'
		read -r -p '选项: ' choice

		case "$choice" in
			1) deploy ;;
			2) install_sqlite ;;
			3) install_mysql ;;
			0) printf '已退出。\n'; return 0 ;;
			*) error '请输入 0 至 3。' ;;
		esac
	done
}

main "$@"
