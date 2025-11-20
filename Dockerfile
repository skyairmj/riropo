# --- Base ---
FROM node:12.22-alpine3.15 AS base

# Set environment variables
ENV NPM_CONFIG_CACHE=/tmp/.npm \
    NODE_ENV=production \
    PATH="$PATH"

# Set package mirrors
RUN npm config set registry https://registry.npmmirror.com
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

# Install build dependencies only when needed
RUN apk add --no-cache --virtual .build-deps \
    pkgconfig \
    python2 \
    make \
    g++ \
    git \
    pixman-dev \
    cairo-dev \
    pango-dev \
    jpeg-dev \
    giflib-dev \
    librsvg-dev \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && apk del .build-deps

# Create app directory and set permissions
WORKDIR /app

# --- Dependencies ---
FROM base AS deps

# Copy only package files for better layer caching
COPY package.json package-lock.json ./

# Install dependencies with cache
RUN --mount=type=cache,target=/tmp/.npm \
    --mount=type=cache,target=/root/.cache \
    npm ci --only=production --silent

# --- Builder ---
FROM base AS builder

# Copy dependencies
COPY --from=deps /app/node_modules ./node_modules

# Copy source code
COPY . .

# Build the application
RUN npm run build

# --- Runner ---
FROM nginx:1.29.3-alpine3.22 AS runner

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copy built assets from builder
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Set correct permissions
RUN chown -R nodejs:nodejs /usr/share/nginx/html && \
    chown -R nodejs:nodejs /var/cache/nginx && \
    chown -R nodejs:nodejs /var/log/nginx && \
    chown -R nodejs:nodejs /etc/nginx/conf.d

# Create nginx PID directory
RUN touch /var/run/nginx.pid && \
    chown -R nodejs:nodejs /var/run/nginx.pid

# Switch to non-root user
USER nodejs

# Expose port 80
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
