# dan-installers

## 一键安装脚本

```bash
curl -fsSL https://raw.githubusercontent.com/zc12120/dan-installers/main/install_dan_gptup_gptmail.sh | bash -s -- install 30
```

## 当前逻辑

- 安装阶段用 `https://gpt-up.icoa.pp.ua/` 拉 `domains`
- 运行阶段自动启动本地 `CPA bridge`
- `CPA bridge` 会把：
  - `/v0/management/domains` 转发到 `gpt-up`
  - 其他 CPA 请求转发到你的 `http://8.220.143.189:8319`

这样可以兼容“你的 CPA 没有 domains 接口，但运行期仍然要接入你自己的 CPA”这个场景。

## ClawCloud Run / 容器部署

本仓库提供了 `Dockerfile` 和 `docker-entrypoint.sh`，可以直接构建镜像。

### 构建

```bash
docker build -t ghcr.io/zc12120/dan-installers:latest .
```

### 运行时环境变量

- `PORT`：容器监听端口，默认 `25666`
- `THREADS`：默认线程数，默认 `30`
- `BRIDGE_PORT`：本地 CPA bridge 端口，默认 `18319`
- `MAIL_API_URL`：默认 `https://gpt-mail.icoa.pp.ua/`
- `MAIL_API_KEY`：默认 `linuxdo`
- `BOOTSTRAP_CPA_BASE_URL`：默认 `https://gpt-up.icoa.pp.ua/`
- `BOOTSTRAP_CPA_TOKEN`：默认 `linuxdo`
- `RUNTIME_CPA_BASE_URL`：默认 `http://8.220.143.189:8319`
- `RUNTIME_CPA_TOKEN`：默认 `Zc@20024611`
- `UPLOAD_API_URL`：默认 `${RUNTIME_CPA_BASE_URL}/v0/management/auth-files`
- `UPLOAD_API_TOKEN`：默认 `${RUNTIME_CPA_TOKEN}`

### 注意

镜像构建阶段会使用 `https://gpt-up.icoa.pp.ua/` 拉 domains；
容器启动阶段会自动起本地 `CPA bridge`，并把配置指向 `http://127.0.0.1:$BRIDGE_PORT`。
同时会把 `config.json` 里的 `upload_api_url` / `upload_api_token` 改成你的 CPA `auth-files` 接口，保证成功凭证会尝试上传到你的 CPA。

## GitHub Container Registry (GHCR)

本仓库已配置 GitHub Actions 自动构建镜像。
当 `main` 分支有新提交时，会自动推送：

- `ghcr.io/zc12120/dan-installers:latest`

在 ClawCloud Run 里可直接填这个镜像地址。
如果 GHCR 包首次默认是 private，请到 GitHub 包页面把它切成 public。

