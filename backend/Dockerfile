FROM node:22-slim AS build
WORKDIR /app
# Prisma's query engine links against OpenSSL, which the -slim base image
# does not ship. Without it Prisma fails to detect/load libssl and the
# app crashes at startup ("Please install OpenSSL... or switch to an image
# that already has OpenSSL installed"). Install it before `prisma generate`.
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*
COPY package*.json ./
COPY prisma ./prisma
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run prisma:generate && npm run build

FROM node:22-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
# Same OpenSSL requirement in the runtime image — this is the one that
# actually runs the app, so the shared library must be present here too.
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*
COPY package*.json ./
COPY prisma ./prisma
RUN npm ci --omit=dev && npm run prisma:generate
COPY openapi.yaml ./
COPY --from=build /app/dist ./dist

EXPOSE 8080
CMD ["node", "dist/index.js"]
