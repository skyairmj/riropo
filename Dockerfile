# --- Base ---
FROM node:12.22-alpine3.15 AS base

# Set environment variables
ENV NPM_CONFIG_CACHE=/tmp/.npm

# Set package mirrors
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

# Create app directory and set permissions
WORKDIR /app

# --- Dependencies ---
FROM base AS deps

# Install build dependencies needed for native modules (canvas, etc.)
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
    && ln -sf /usr/bin/python2 /usr/bin/python

# Copy only package files for better layer caching
COPY package.json package-lock.json ./

# Install dependencies with cache
RUN --mount=type=cache,target=/tmp/.npm \
    npm config set python /usr/bin/python && \
    npm config set registry https://registry.npmmirror.com && \
    npm install --prefer-offline

# Clean up build dependencies after installation
RUN apk del .build-deps

# --- Builder ---
FROM base AS builder

ENV NODE_ENV=production

# Copy dependencies
COPY --from=deps /app/node_modules ./node_modules

# Copy source code
COPY . .

# Build the application
RUN npm run build

# --- Runner ---
FROM nginx:1.29.3-alpine3.22 AS runner

ENV NODE_ENV=production

# Copy built assets from builder
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Set correct permissions
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    chown -R nginx:nginx /etc/nginx/conf.d

# Create nginx PID directory
RUN touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

# Switch to non-root user
USER nginx

# Expose port 80
EXPOSE 80

# Health check
HEALTHCHECK --interval=300s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
