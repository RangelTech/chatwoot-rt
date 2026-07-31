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

COPY chatwoot/entrypoints/web.sh /usr/local/bin/rt-web.sh
COPY chatwoot/entrypoints/worker.sh /usr/local/bin/rt-worker.sh
RUN chmod +x /usr/local/bin/rt-web.sh /usr/local/bin/rt-worker.sh

# Cloud Run injeta PORT; o Chatwoot escuta em 3000 por padrão.
ENV PORT=3000
EXPOSE 3000

CMD ["/usr/local/bin/rt-web.sh"]
