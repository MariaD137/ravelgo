# Pulled from ECR Public's mirror of the official Docker Hub image, not
# docker.io directly: CodeBuild's IP range is shared across many AWS
# customers and routinely exhausts Docker Hub's anonymous-pull rate limit
# ("429 Too Many Requests" on the very first FROM). ECR Public mirrors the
# same official image with a separate, much higher quota, so builds inside
# AWS (CodeBuild, CodePipeline, etc.) don't compete with the public internet
# for pulls.
FROM public.ecr.aws/docker/library/node:22-slim AS build
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

FROM public.ecr.aws/docker/library/node:22-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
# Stamped by CI (`--build-arg GIT_SHA=$GITHUB_SHA`) so a running container can
# report exactly which commit it was built from via GET /health — the only
# way to tell "deploy reported success" apart from "the new code is actually
# serving" without App Runner console/log access. Defaults to "unknown" for a
# local `docker build` with no arg, which is expected and harmless.
ARG GIT_SHA=unknown
ENV GIT_SHA=$GIT_SHA
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
