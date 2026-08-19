# Chatwoot Rangel Tech — fork de verdade (a partir de v4.16.2).
#
# Até 18/08/2026 este arquivo só empacotava a imagem oficial
# (`FROM chatwoot/chatwoot:v3.16.0`) com branding + entrypoint por cima —
# comentário explícito "não é fork". Isso parou de ser suficiente quando
# apareceram mudanças que exigem editar código Ruby do Chatwoot (AI Assist
# apontando pro 9Router por tenant, produto-06). A partir daqui o build
# compila a própria árvore fonte vendorizada em `chatwoot/` (validada em
# staging isolado via upgrade de 2 hops v3.16.0→v4.1.0→v4.16.2, ver
# `agent-llm-staging-chatwoot-upgrade/`), não mais um `docker pull` de tag.
#
# Consequência que já era esperada (produto-06 seção 0): upgrade de versão
# deixa de ser "trocar a tag" e vira "vendorizar a nova versão + reaplicar os
# patches" — mesmo modelo de manutenção já usado no 9Router e no kernel-llm.
#
# Build multi-stage adaptado do `chatwoot/docker/Dockerfile` oficial da
# v4.16.2, só com os caminhos prefixados por `chatwoot/` porque o contexto de
# build continua sendo a raiz deste repo (mesmo motivo de sempre: os
# entrypoints usam caminho relativo pra não serem reescritos pelo Git Bash no
# Windows).

# pre-build stage
FROM node:24-alpine AS node
FROM ruby:3.4.4-alpine3.21 AS pre-builder

ARG NODE_VERSION="24.13.0"
ARG PNPM_VERSION="10.2.0"
ENV NODE_VERSION=${NODE_VERSION}
ENV PNPM_VERSION=${PNPM_VERSION}

ARG BUNDLE_WITHOUT="development:test"
ENV BUNDLE_WITHOUT=${BUNDLE_WITHOUT}
ENV BUNDLER_VERSION=2.5.16

ARG RAILS_SERVE_STATIC_FILES=true
ENV RAILS_SERVE_STATIC_FILES=${RAILS_SERVE_STATIC_FILES}

ARG RAILS_ENV=production
ENV RAILS_ENV=${RAILS_ENV}

ARG NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider"
ENV NODE_OPTIONS=${NODE_OPTIONS}

ENV BUNDLE_PATH="/gems"

RUN apk update && apk add --no-cache \
  openssl \
  tar \
  build-base \
  tzdata \
  postgresql-dev \
  postgresql-client \
  git \
  curl \
  xz \
  && mkdir -p /var/app \
  && gem install bundler -v "$BUNDLER_VERSION"

COPY --from=node /usr/local/bin/node /usr/local/bin/
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

RUN npm install -g pnpm@${PNPM_VERSION}

ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

WORKDIR /app

COPY chatwoot/Gemfile chatwoot/Gemfile.lock ./

# compilar grpc/protobuf nativamente pra musl (dialogflow) + xz pro libxml do
# nokogiri — mesmas notas do Dockerfile oficial.
RUN apk update && apk add --no-cache build-base musl ruby-full ruby-dev gcc make musl-dev openssl openssl-dev g++ linux-headers xz vips
RUN bundle config set --local force_ruby_platform true

RUN if [ "$RAILS_ENV" = "production" ]; then \
  bundle config set without 'development test'; bundle install -j 4 -r 3; \
  else bundle install -j 4 -r 3; \
  fi

COPY chatwoot/package.json chatwoot/pnpm-lock.yaml ./
RUN pnpm i

COPY chatwoot/ /app

# Branding + entrypoints + scripts/ops entram aqui, ANTES do precompile, pra
# que os assets de marca já sejam empacotados no bundle de produção. Mesmo
# mecanismo de sempre: nenhum arquivo de código do Chatwoot é editado por
# esta sobreposição, ela só adiciona arquivos.
COPY chatwoot/branding/ /app/public/brand-assets/
COPY chatwoot/entrypoints/web.sh /app/rt-web.sh
COPY chatwoot/entrypoints/worker.sh /app/rt-worker.sh
RUN chmod +x /app/rt-web.sh /app/rt-worker.sh
COPY scripts/ops/ /app/scripts/ops/

RUN mkdir -p /app/log

RUN if [ "$RAILS_ENV" = "production" ]; then \
  SECRET_KEY_BASE=precompile_placeholder RAILS_LOG_TO_STDOUT=enabled bundle exec rake assets:precompile \
  && rm -rf spec node_modules tmp/cache; \
  fi

RUN rm -rf /gems/ruby/3.4.0/cache/*.gem \
  && find /gems/ruby/3.4.0/gems/ \( -name "*.c" -o -name "*.o" \) -delete

# final build stage
FROM ruby:3.4.4-alpine3.21

ARG NODE_VERSION="24.13.0"
ENV NODE_VERSION=${NODE_VERSION}

ARG BUNDLE_WITHOUT="development:test"
ENV BUNDLE_WITHOUT=${BUNDLE_WITHOUT}
ENV BUNDLER_VERSION=2.5.16

ARG EXECJS_RUNTIME="Disabled"
ENV EXECJS_RUNTIME=${EXECJS_RUNTIME}

ARG RAILS_SERVE_STATIC_FILES=true
ENV RAILS_SERVE_STATIC_FILES=${RAILS_SERVE_STATIC_FILES}

ARG BUNDLE_FORCE_RUBY_PLATFORM=1
ENV BUNDLE_FORCE_RUBY_PLATFORM=${BUNDLE_FORCE_RUBY_PLATFORM}

ARG RAILS_ENV=production
ENV RAILS_ENV=${RAILS_ENV}
ENV BUNDLE_PATH="/gems"

RUN apk update && apk add --no-cache \
  build-base \
  openssl \
  tzdata \
  postgresql-client \
  imagemagick \
  git \
  vips \
  && gem install bundler -v "$BUNDLER_VERSION"

COPY --from=node /usr/local/bin/node /usr/local/bin/
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules

COPY --from=pre-builder /gems/ /gems/
COPY --from=pre-builder /app /app

WORKDIR /app

# Cloud Run injeta PORT; o Chatwoot escuta em 3000 por padrão.
ENV PORT=3000
EXPOSE 3000

CMD ["./rt-web.sh"]
