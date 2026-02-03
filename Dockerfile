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
# Use YOUR fork, not the original repo!
RUN git clone --depth 1 --branch "${OPENCLAW_GIT_REF}" https://github.com/Saurabh2414/openclaw.git .

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

# Verify UI build succeeded
RUN echo "=== Verifying UI Build ===" && \
    if [ -d "/openclaw/ui/dist" ] && [ "$(ls -A /openclaw/ui/dist 2>/dev/null)" ]; then \
        echo "✓ UI build successful: $(ls /openclaw/ui/dist | wc -l) files"; \
    else \
        echo "✗ ERROR: UI build failed!"; \
        ls -la /openclaw/ui/ 2>/dev/null || true; \
        exit 1; \
    fi

# STAGE 2: Final Runtime Image
FROM node:22-bookworm
ENV NODE_ENV=production

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl pkill \
  && rm -rf /var/lib/apt/lists/*

# Install pnpm globally for maintenance
RUN npm install -g pnpm

WORKDIR /app

# Copy built files
COPY --from=openclaw-build /openclaw /openclaw

# Verify UI assets in final image
RUN echo "=== Checking UI assets in final image ===" && \
    if [ -d "/openclaw/ui/dist" ] && [ "$(ls -A /openclaw/ui/dist 2>/dev/null)" ]; then \
        echo "✓ UI assets found: $(ls /openclaw/ui/dist | wc -l) files"; \
    else \
        echo "✗ ERROR: UI assets missing or empty!"; \
        ls -la /openclaw/ui/ 2>/dev/null || true; \
        exit 1; \
    fi

# Install Chromium (Assistant's "Eyes")
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

# --- CRITICAL CONFIGURATION ---
# Fixes "Assets not found" (Must be OPENCLAW_UI_PATH)
ENV OPENCLAW_UI_PATH=/openclaw/ui/dist
# Fixes "Disconnected (1008)" - Trusts Railway internal network
ENV OPENCLAW_GATEWAY_TRUSTED_PROXIES=127.0.0.1,10.0.0.0/8,100.64.0.0/10
# Browser config
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
# Port config
ENV PORT=8080
ENV OPENCLAW_PUBLIC_PORT=8080

EXPOSE 8080

# --- STARTUP WITH SELF-HEALING ---
CMD ["sh", "-c", "mkdir -p /data/.openclaw/agents/main/sessions/ && find /data/.openclaw/agents/main/sessions/ -name '*.lock' -delete 2>/dev/null || true && node src/server.js"]
