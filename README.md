# dan-installers

## 一键安装脚本

```bash
curl -fsSL https://raw.githubusercontent.com/zc12120/dan-installers/main/install_dan_gptup_gptmail.sh | bash -s -- install 20
```

## ClawCloud Run / 容器部署

本仓库提供了 `Dockerfile` 和 `docker-entrypoint.sh`，可以直接构建镜像。

### 构建

```bash
docker build -t ghcr.io/zc12120/dan-installers:latest .
```

### 运行时环境变量

- `PORT`：容器监听端口，默认 `25666`
- `THREADS`：默认线程数，默认 `20`
- `MAIL_API_URL`：默认 `https://gpt-mail.icoa.pp.ua/`
- `MAIL_API_KEY`：默认 `linuxdo`
- `RUNTIME_CPA_BASE_URL`：默认 `http://8.220.143.189:8319`
- `RUNTIME_CPA_TOKEN`：默认 `114514`

### 注意

镜像构建阶段会使用 `https://gpt-up.icoa.pp.ua/` 拉 domains；
容器启动阶段会自动把配置切回你自己的 CPA。
