# 🚀 DUALEAPA Sprint 1 - Multi-Stage Production Dockerfile
# Optimized for security, performance, and flexibility across the stack
# Supports: Node.js Backend, React Frontend, Python Data Services

# ============================================================================
# STAGE 1: Dependencies Builder - Lightweight Alpine Base
# ============================================================================
FROM node:20-alpine AS dependencies
LABEL maintainer="DualEAPA Team"
LABEL description="Multi-stack production application with security hardening"

WORKDIR /app

# Install build dependencies with cache optimization
RUN apk add --no-cache --virtual .build-deps \
    python3 \
    make \
    g++ \
    && npm install -g pnpm yarn

# Copy package files for dependency caching
COPY package*.json pnpm-lock.yaml* yarn.lock* ./

# Install dependencies
RUN npm ci --prefer-offline --no-audit || yarn install --frozen-lockfile || pnpm install --frozen-lockfile

# ============================================================================
# STAGE 2: Build Optimizer - Frontend & Backend Compilation
# ============================================================================
FROM node:20-alpine AS builder

WORKDIR /app

# Copy node_modules from dependencies stage
COPY --from=dependencies /app/node_modules ./node_modules
COPY --from=dependencies /app/package*.json ./

# Copy source code
COPY . .

# Build frontend (if React/Vue/Next.js exists)
RUN if [ -d "frontend" ]; then npm run build:frontend || echo "No frontend build"; fi

# Build backend (if TypeScript/Node exists)
RUN if [ -d "backend" ]; then npm run build:backend || echo "No backend build"; fi

# ============================================================================
# STAGE 3: Production Runtime - Secured & Minimal
# ============================================================================
FROM node:20-alpine

# Security: Create non-root user
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001

WORKDIR /app

# Copy only production dependencies and built artifacts
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/dist ./dist
COPY --from=builder --chown=nodejs:nodejs /app/build ./build
COPY --from=builder --chown=nodejs:nodejs /app/public ./public
COPY --from=builder --chown=nodejs:nodejs /app/package*.json ./

# Copy environment configuration (update as needed)
COPY .env.production* ./

# Install runtime-only dependencies
RUN apk add --no-cache \
    curl \
    ca-certificates \
    tini && \
    npm cache clean --force

# Health check configuration
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PORT:-3000}/health || exit 1

# Security: Use non-root user
USER nodejs

# Expose application port
EXPOSE ${PORT:-3000}

# Use tini to handle signals properly
ENTRYPOINT ["/sbin/tini", "--"]

# Default command
CMD ["npm", "start"]

# ============================================================================
# STAGE 4: Development Environment (Optional)
# ============================================================================
FROM node:20-alpine AS development

WORKDIR /app

# Install dev tools
RUN apk add --no-cache \
    git \
    curl \
    vim \
    python3 \
    make \
    g++ && \
    npm install -g pnpm yarn debug

# Copy everything for development
COPY . .

# Install all dependencies
RUN npm ci

# Expose ports for dev server, API, and debugger
EXPOSE 3000 5000 9229

# Development command
CMD ["npm", "run", "dev"]
