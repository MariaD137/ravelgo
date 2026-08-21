FROM node:22-slim AS build
WORKDIR /app
COPY package*.json ./
COPY prisma ./prisma
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run prisma:generate && npm run build

FROM node:22-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
COPY prisma ./prisma
RUN npm ci --omit=dev && npm run prisma:generate
COPY openapi.yaml ./
COPY --from=build /app/dist ./dist

# Runs as the non-root `node` user the base image already provides —
# nothing in this app writes to disk at runtime (uploads go straight to S3
# via presigned URLs, logs go to stdout/stderr), so this has no functional
# effect, only a smaller blast radius if the process is ever compromised.
RUN chown -R node:node /app
USER node

EXPOSE 8080
CMD ["node", "dist/index.js"]
