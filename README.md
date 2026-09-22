# Z-BlogPHP 工具集

用于 Z-BlogPHP 网站部署、管理和插件同步的 Bash 脚本工具。

## 目录结构

```plaintext
bin/
├── zbp.sh                   # Z-BlogPHP 部署和管理脚本
├── sync.sh                  # 插件同步脚本
├── .env                     # 环境变量配置文件（需从 .env.example 复制并配置）
├── .env.example             # 环境变量配置示例
├── bundle_apps.json         # 应用包配置文件（示例见 bundle_apps.example.json）
└── bundle_apps.example.json # 应用包配置示例

```

## 安装要求

- Bash / Git Bash
- Git
- PHP 7.4+
- rsync
- unzip
- find

## 配置

1. 复制配置文件模板：

```bash
cp bin/.env.example bin/.env
cp bin/bundle_apps.example.json bin/bundle_apps.json

```

2. 编辑 `bin/.env` 文件，配置以下变量：

- `ZBP17_WORKTREE` / `ZBP17_WEB_ROOT`：Z-BlogPHP 1.7 的 Git 工作树和部署目录
- `ZBP18_WORKTREE` / `ZBP18_WEB_ROOT`：Z-BlogPHP 1.8 的 Git 工作树和部署目录
- `ZBP_ARCHIVE_DIR`：归档文件存储目录
- 数据库配置（如使用 MySQL）

3. 编辑 `bin/bundle_apps.json` 文件，用于从应用中心或指定网址下载应用解压到部署目录。

注：对于本地使用，github 地址就不太适合，建议使用本地服务器地址。

## 使用方法

### 部署 Z-BlogPHP

```bash
cd bin
./zbp.sh

```

功能选项：
1. 本地打包并部署
2. CLI 安装 SQLite
3. CLI 安装 MySQL
4. 从 bundle 下载并安装应用

### 同步插件

用于将放置在本地的插件同步到目标 Z-BlogPHP 站点。

在 `.env` 文件中配置。

```bash
cd bin
./sync.sh

```

功能：
- 选择目标站点（zbp17 或 zbp18）
- 选择要同步的插件
- 使用 rsync 同步到目标目录

## 注意事项

- 所有路径需根据实际环境配置
