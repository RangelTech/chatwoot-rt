# Chatwoot Community, empacotado — não é fork.
#
# A imagem oficial entra como base e só recebe sobreposição de branding e um
# entrypoint próprio. Isso mantém o `docker pull` de uma versão nova como o
# caminho de atualização, em vez de merge de upstream num fork.
ARG CHATWOOT_VERSION=v3.16.0
FROM chatwoot/chatwoot:${CHATWOOT_VERSION}

# Branding externo: logos, favicon e textos sobrepostos sobre os assets
# públicos. Nenhum arquivo de código do Chatwoot é modificado.
COPY chatwoot/branding/ /app/public/brand-assets/

# Os entrypoints ficam no WORKDIR (/app) de propósito: o comando do Cloud Run
# é passado como caminho relativo (./rt-web.sh) para não ser reescrito por
# shells que traduzem caminhos absolutos (Git Bash no Windows faz isso).
COPY chatwoot/entrypoints/web.sh ./rt-web.sh
COPY chatwoot/entrypoints/worker.sh ./rt-worker.sh
RUN chmod +x ./rt-web.sh ./rt-worker.sh

# Cloud Run injeta PORT; o Chatwoot escuta em 3000 por padrão.
ENV PORT=3000
EXPOSE 3000

CMD ["./rt-web.sh"]
