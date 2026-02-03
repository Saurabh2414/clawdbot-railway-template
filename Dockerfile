# STAGE 1: Build OpenClaw from source
FROM node:22-bookworm AS openclaw-build

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git ca-certificates curl python3 make g++ \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"
RUN corepack enable

WORKDIR /openclaw
ARG OPENCLAW_GIT_REF=main
RUN git clone --depth 1 --branch "${OPENCLAW_GIT_REF}" https://github.com/openclaw/openclaw.git .

# Patch for workspace protocols
RUN set -eux; \
  find ./extensions -name 'package.json' -type f | while read -r f; do \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
  done

RUN pnpm install --no-frozen-lockfile
RUN pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:install && pnpm ui:build

# Verify UI build
RUN echo "=== UI Build Verification ===" && \
    echo "UI files in /openclaw/ui/dist:" && \
    ls -la /openclaw/ui/dist/ || echo "No dist directory!" && \
    echo "UI directory contents:" && \
    ls -la /openclaw/ui/ || echo "No ui directory!"

# STAGE 2: Final Runtime Image
FROM node:22-bookworm
ENV NODE_ENV=production

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl pkill \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g pnpm

WORKDIR /app

# Copy built files
COPY --from=openclaw-build /openclaw /openclaw

# Debug: Show what was copied
RUN echo "=== Verifying copied files ===" && \
    echo "Checking /openclaw/ui/dist:" && \
    ls -la /openclaw/ui/dist/ 2>/dev/null || echo "ERROR: /openclaw/ui/dist not found!" && \
    echo "Total files in /openclaw/ui/dist:" && \
    find /openclaw/ui/dist -type f 2>/dev/null | wc -l

# Install Chromium
RUN apt-get update && apt-get install -y \
    chromium \
    fonts-ipafont-gothic \
    fonts-wqy-zenhei \
    fonts-thai-tlwg \
    fonts-kacst \
    fonts-freefont-ttf \
    libxss1 \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Create OpenClaw CLI link
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /openclaw/dist/entry.js "$@"' > /usr/local/bin/openclaw \
  && chmod +x /usr/local/bin/openclaw

# Copy Wrapper files
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force
COPY src ./src

# --- TRY ALL POSSIBLE ENVIRONMENT VARIABLES ---
ENV OPENCLAW_UI_PATH=/openclaw/ui/dist
ENV OPENCLAW_UI_ASSETS_PATH=/openclaw/ui/dist
ENV OPENCLAW_UI_DIST=/openclaw/ui/dist
ENV UI_ASSETS_PATH=/openclaw/ui/dist

# Other config
ENV OPENCLAW_GATEWAY_TRUSTED_PROXIES=127.0.0.1,10.0.0.0/8,100.64.0.0/10
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV PORT=8080
ENV OPENCLAW_PUBLIC_PORT=8080

EXPOSE 8080

# --- STARTUP WITH DEBUGGING ---
CMD ["sh", "-c", "echo '=== Environment Variables ===' && env | grep -i ui && echo '=== Checking UI files ===' && ls -la /openclaw/ui/dist/ 2>/dev/null || echo 'UI dist not found!' && echo '=== Starting... ===' && mkdir -p /data/.openclaw/agents/main/sessions/ && find /data/.openclaw/agents/main/sessions/ -name '*.lock' -delete 2>/dev/null || true && sleep 2 && node src/server.js"]
