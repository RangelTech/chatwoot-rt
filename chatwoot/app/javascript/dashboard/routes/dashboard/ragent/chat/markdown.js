// Renderização segura da resposta do agente (spec 10, 15.2 item C).
//
// - `markdown`: Markdown completo (markdown-it com HTML cru DESLIGADO) e depois DOMPurify com
//   lista fechada de tags/atributos. Links abrem em outra aba com rel=noopener noreferrer.
// - `whatsapp`: texto simples respeitando *negrito*, _itálico_, ~tachado~ e ```mono``` do WhatsApp.
// - `text`: texto simples, nada interpretado.
//
// A resposta é dividida em blocos de nível raiz (parágrafo, lista, tabela, código...). Cada bloco
// vira uma string de HTML independente: durante o stream só o último bloco muda, os anteriores
// mantêm a mesma string e o Vue não toca no DOM deles (sem piscar, imagens não recarregam).
import MarkdownIt from 'markdown-it';
import DOMPurify from 'dompurify';

export const FORMATS = ['markdown', 'whatsapp', 'text'];
export const normalizeFormat = format =>
  FORMATS.includes(format) ? format : 'markdown';

const ALLOWED_TAGS = [
  'p',
  'br',
  'hr',
  'strong',
  'b',
  'em',
  'i',
  'del',
  's',
  'code',
  'pre',
  'blockquote',
  'ul',
  'ol',
  'li',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'a',
  'img',
  'table',
  'thead',
  'tbody',
  'tr',
  'th',
  'td',
  'span',
  'div',
  'sup',
  'sub',
  'button',
];
const ALLOWED_ATTR = [
  'href',
  'src',
  'alt',
  'title',
  'class',
  'colspan',
  'rowspan',
  'align',
  'start',
  'type',
  'target',
  'rel',
  'loading',
  'referrerpolicy',
  'aria-label',
];
// Esquemas aceitos em href/src: http(s), mailto e tel (javascript:, data:, vbscript: etc. caem).
// Valores sem esquema (ex.: loading="lazy", âncoras, caminhos) passam por este mesmo teste.
const ALLOWED_URI =
  /^(?:(?:https?|mailto|tel):|[^a-z]|[a-z+.-]+(?:[^a-z+.:-]|$))/i;
const ARTIFACT_PREFIX = 'artifact:';
const MAX_CACHE = 800;

const DEFAULT_LABELS = { copy: 'Copiar', copied: 'Copiado' };

const escapeHtml = value =>
  String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

const createMarkdown = () => {
  const md = new MarkdownIt({
    html: false,
    linkify: true,
    breaks: true,
    typographer: false,
  });
  const defaultValidate = md.validateLink.bind(md);
  // `artifact:<id ou nome>` aponta para um arquivo gerado pelo agente (resolvido no componente).
  md.validateLink = url =>
    url.trim().toLowerCase().startsWith(ARTIFACT_PREFIX) ||
    defaultValidate(url);

  md.renderer.rules.fence = (tokens, idx, options, env) => {
    const token = tokens[idx];
    const lang = (token.info || '')
      .trim()
      .split(/\s+/)[0]
      .replace(/[^a-z0-9_+#.-]/gi, '');
    const labels = { ...DEFAULT_LABELS, ...(env?.labels || {}) };
    const code = escapeHtml(token.content.replace(/\n$/, ''));
    const cls = lang ? ` class="language-${escapeHtml(lang)}"` : '';
    return (
      '<div class="rt-md-code"><div class="rt-md-code-bar">' +
      `<span>${escapeHtml(lang)}</span>` +
      '<button type="button" class="rt-md-copy" data-copy-code="1" ' +
      `aria-label="${escapeHtml(labels.copy)}">${escapeHtml(labels.copy)}</button>` +
      `</div><pre><code${cls}>${code}</code></pre></div>`
    );
  };
  md.renderer.rules.code_block = (tokens, idx, options, env) =>
    md.renderer.rules.fence(tokens, idx, options, env);

  md.renderer.rules.image = (tokens, idx) => {
    const token = tokens[idx];
    const src = (token.attrGet('src') || '').trim();
    const alt = escapeHtml(token.content || '');
    const title = token.attrGet('title');
    const titleAttr = title ? ` title="${escapeHtml(title)}"` : '';
    if (/^https?:\/\//i.test(src)) {
      return `<img src="${escapeHtml(src)}" alt="${alt}"${titleAttr} class="rt-md-img" loading="lazy" referrerpolicy="no-referrer">`;
    }
    // qualquer outro caminho é lido como arquivo gerado (artefato) e resolvido pelo componente
    const ref = src.replace(/^artifact:/i, '').replace(/^\.?\/+/, '');
    return `<img alt="${alt}"${titleAttr} class="rt-md-img rt-md-artifact" data-artifact-ref="${escapeHtml(ref)}">`;
  };
  return md;
};

const createPurifier = win => {
  const purify = DOMPurify(win);
  purify.addHook('afterSanitizeAttributes', node => {
    const tag = (node.tagName || '').toLowerCase();
    if (tag === 'a') {
      if (node.getAttribute('href')) {
        node.setAttribute('target', '_blank');
        node.setAttribute('rel', 'noopener noreferrer');
      } else {
        node.removeAttribute('target');
        node.removeAttribute('rel');
      }
    } else if (tag === 'img') {
      node.setAttribute('referrerpolicy', 'no-referrer');
    } else if (tag === 'button') {
      node.setAttribute('type', 'button');
    }
  });
  const config = {
    ALLOWED_TAGS,
    ALLOWED_ATTR,
    ALLOWED_URI_REGEXP: ALLOWED_URI,
    ALLOW_DATA_ATTR: false,
    ALLOW_ARIA_ATTR: false,
    FORBID_TAGS: [
      'style',
      'script',
      'iframe',
      'object',
      'embed',
      'form',
      'input',
    ],
    FORBID_ATTR: ['style'],
  };
  // atributos data-* próprios, liberados um a um (o resto de data-* continua bloqueado)
  const extra = ['data-copy-code', 'data-artifact-ref'];
  return html =>
    purify.sanitize(html, {
      ...config,
      ADD_ATTR: extra,
      RETURN_TRUSTED_TYPE: false,
    });
};

// ----------------------------------------------------------- WhatsApp
const wrapInline = (text, marker, tag) => {
  const m = marker.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(
    `(^|[^\\w${m}])${m}([^\\s${m}](?:[^${m}\\n]*[^\\s${m}])?)${m}(?![\\w${m}])`,
    'g'
  );
  return text.replace(re, `$1<${tag}>$2</${tag}>`);
};

// Converte o texto do WhatsApp em HTML seguro (tudo escapado antes; só 4 formatações).
export const whatsappToHtml = text => {
  const keep = [];
  const hold = html => {
    keep.push(html);
    return `\u0000${keep.length - 1}\u0000`;
  };
  let out = String(text || '').replace(/```([\s\S]*?)```/g, (_, code) =>
    hold(
      `<code class="rt-md-inline">${escapeHtml(code.replace(/^\n|\n$/g, ''))}</code>`
    )
  );
  out = escapeHtml(out);
  out = wrapInline(out, '*', 'strong');
  out = wrapInline(out, '_', 'em');
  out = wrapInline(out, '~', 'del');
  // eslint-disable-next-line no-control-regex
  return out.replace(/\u0000(\d+)\u0000/g, (_, i) => keep[Number(i)]);
};

// ----------------------------------------------------------- fábrica
export const createRenderer = ({ window: win } = {}) => {
  const md = createMarkdown();
  const sanitize = createPurifier(win || window);
  const cache = new Map();

  const clean = html => {
    if (cache.has(html)) return cache.get(html);
    const safe = sanitize(html);
    if (cache.size >= MAX_CACHE) cache.clear();
    cache.set(html, safe);
    return safe;
  };

  // Tokens de nível raiz agrupados por bloco.
  const segments = tokens => {
    const result = [];
    let current = [];
    let depth = 0;
    tokens.forEach(token => {
      current.push(token);
      depth += token.nesting;
      if (depth === 0) {
        result.push(current);
        current = [];
      }
    });
    if (current.length) result.push(current);
    return result;
  };

  const renderBlocks = (text, { format = 'markdown', labels } = {}) => {
    const source = String(text || '');
    if (!source.trim()) return [];
    const fmt = normalizeFormat(format);
    if (fmt === 'text') return [clean(`<p>${escapeHtml(source)}</p>`)];
    if (fmt === 'whatsapp') return [clean(`<p>${whatsappToHtml(source)}</p>`)];
    const env = { labels };
    return segments(md.parse(source, env)).map(group =>
      clean(md.renderer.render(group, md.options, env))
    );
  };

  const render = (text, options) => renderBlocks(text, options).join('');
  return { render, renderBlocks, sanitize: clean };
};

let shared = null;
export const getRenderer = () => {
  if (!shared) shared = createRenderer();
  return shared;
};
