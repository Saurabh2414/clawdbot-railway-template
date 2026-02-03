FROM node:20-alpine

# Install dependencies
RUN apk add --no-cache \
    git \
    python3 \
    make \
    g++ \
    chromium \
    nss \
    freetype \
    harfbuzz \
    ca-certificates \
    ttf-freefont \
    font-noto-emoji \
    curl

# Install pnpm
RUN npm install -g pnpm

WORKDIR /app

# Clone your fork (replace YOUR_USERNAME with your GitHub username)
RUN git clone --depth 1 https://github.com/YOUR_USERNAME/openclaw.git openclaw

WORKDIR /app/openclaw

# Install and build
RUN pnpm install --no-frozen-lockfile
RUN pnpm build
RUN pnpm ui:install && pnpm ui:build

# Verify UI was built
RUN ls -la ui/dist/ || echo "UI build may have failed" && \
    find ui/dist -type f -name "*.html" | head -5

# Set environment variables
ENV NODE_ENV=production
ENV OPENCLAW_UI_PATH=/app/openclaw/ui/dist
ENV OPENCLAW_UI_ASSETS=/app/openclaw/ui/dist
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
ENV OPENCLAW_GATEWAY_TRUSTED_PROXIES=127.0.0.1,10.0.0.0/8,100.64.0.0/10
ENV PORT=8080
ENV OPENCLAW_PUBLIC_PORT=8080

# Create startup script
RUN printf '%s\n' \
  '#!/bin/sh' \
  'echo "=== Starting OpenClaw ==="' \
  'echo "UI path: $OPENCLAW_UI_PATH"' \
  'echo "Checking UI files..."' \
  'ls -la /app/openclaw/ui/dist/ 2>/dev/null || echo "Warning: UI dist not found"' \
  'mkdir -p /data/.openclaw/agents/main/sessions/' \
  'find /data/.openclaw/agents/main/sessions/ -name "*.lock" -delete 2>/dev/null || true' \
  'sleep 2' \
  'echo "Starting server..."' \
  'exec node /app/openclaw/dist/entry.js' > /start.sh \
  && chmod +x /start.sh

EXPOSE 8080

CMD ["/start.sh"]
