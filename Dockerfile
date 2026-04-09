FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    INSTALL_DIR=/opt/dan-runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends bash curl ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*

ARG BOOTSTRAP_CPA_BASE_URL=https://gpt-up.icoa.pp.ua/
ARG BOOTSTRAP_CPA_TOKEN=linuxdo
ARG MAIL_API_URL=https://gpt-mail.icoa.pp.ua/
ARG MAIL_API_KEY=linuxdo
ARG THREADS=30
ARG DAN_PORT=25666

RUN mkdir -p "$INSTALL_DIR"
RUN curl -fsSL https://raw.githubusercontent.com/uton88/dan-binary-releases/main/install.sh | bash -s -- \
    --install-dir "$INSTALL_DIR" \
    --cpa-base-url "$BOOTSTRAP_CPA_BASE_URL" \
    --cpa-token "$BOOTSTRAP_CPA_TOKEN" \
    --mail-api-url "$MAIL_API_URL" \
    --mail-api-key "$MAIL_API_KEY" \
    --threads "$THREADS" \
    --port "$DAN_PORT"

COPY cpa-bridge.py /usr/local/bin/cpa-bridge.py
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/bin/cpa-bridge.py \
    && rm -f "$INSTALL_DIR/dan-web.log" "$INSTALL_DIR/dan-web.pid"

WORKDIR /opt/dan-runtime
EXPOSE 25666
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

