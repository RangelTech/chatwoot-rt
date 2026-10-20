import { describe, it, expect } from 'vitest';
import { createRenderer, normalizeFormat, whatsappToHtml } from './markdown';

const r = createRenderer({ window });
const html = (text, options) => r.render(text, options);

describe('normalizeFormat', () => {
  it('aceita só os três formatos e cai em markdown', () => {
    expect(normalizeFormat('whatsapp')).toBe('whatsapp');
    expect(normalizeFormat('text')).toBe('text');
    expect(normalizeFormat('html')).toBe('markdown');
    expect(normalizeFormat(undefined)).toBe('markdown');
  });
});

describe('markdown: estrutura', () => {
  it('renderiza títulos, listas, ênfase e citações', () => {
    const out = html(
      '# Título\n\n- um\n- **dois**\n\n1. a\n2. *b*\n\n> citação\n\n~~riscado~~'
    );
    expect(out).toContain('<h1>Título</h1>');
    expect(out).toContain('<ul>');
    expect(out).toContain('<strong>dois</strong>');
    expect(out).toContain('<ol>');
    expect(out).toContain('<em>b</em>');
    expect(out).toContain('<blockquote>');
    expect(out).toContain('<s>riscado</s>');
  });

  it('renderiza tabelas', () => {
    const out = html('| a | b |\n|---|---|\n| 1 | 2 |\n');
    expect(out).toContain('<table>');
    expect(out).toContain('<th>a</th>');
    expect(out).toContain('<td>2</td>');
  });

  it('renderiza bloco de código com botão de copiar e escapa o conteúdo', () => {
    const out = html('```js\nconst a = "<b>x</b>";\n```', {
      labels: { copy: 'Copiar' },
    });
    expect(out).toContain('rt-md-code');
    expect(out).toContain('language-js');
    expect(out).toContain('data-copy-code');
    expect(out).toContain('>Copiar</button>');
    expect(out).toContain('&lt;b&gt;x&lt;/b&gt;');
    expect(out).not.toContain('<b>x</b>');
  });

  it('código inline e quebras de linha', () => {
    const out = html('use `rm` agora\nlinha 2');
    expect(out).toContain('<code>rm</code>');
    expect(out).toContain('<br>');
  });
});

describe('markdown: links e imagens', () => {
  it('links externos abrem em outra aba com rel seguro', () => {
    const out = html('[site](https://exemplo.com/a?b=1) e https://auto.link/x');
    const doc = new DOMParser().parseFromString(out, 'text/html');
    const links = [...doc.querySelectorAll('a')];
    expect(links).toHaveLength(2);
    links.forEach(a => {
      expect(a.getAttribute('target')).toBe('_blank');
      expect(a.getAttribute('rel')).toBe('noopener noreferrer');
    });
  });

  it('esquemas perigosos viram texto, sem link', () => {
    const out = html(
      '[a](javascript:alert(1)) [b](vbscript:x) [c](data:text/html;base64,AAAA) [d](file:///etc/passwd)'
    );
    const doc = new DOMParser().parseFromString(out, 'text/html');
    expect(doc.querySelectorAll('a')).toHaveLength(0);
    expect(doc.querySelectorAll('[href],[src]')).toHaveLength(0);
  });

  it('imagem https mantém src e referrerpolicy; sem rastreio de referer', () => {
    const out = html('![gráfico](https://cdn.exemplo.com/g.png)');
    const img = new DOMParser()
      .parseFromString(out, 'text/html')
      .querySelector('img');
    expect(img.getAttribute('src')).toBe('https://cdn.exemplo.com/g.png');
    expect(img.getAttribute('alt')).toBe('gráfico');
    expect(img.getAttribute('referrerpolicy')).toBe('no-referrer');
    expect(img.getAttribute('loading')).toBe('lazy');
  });

  it('imagem de artefato não leva src: o componente resolve pelo nome/id', () => {
    const out = html('![vendas](artifact:grafico.png) ![x](./arquivos/b.png)');
    const imgs = [
      ...new DOMParser()
        .parseFromString(out, 'text/html')
        .querySelectorAll('img'),
    ];
    expect(imgs.map(i => i.getAttribute('data-artifact-ref'))).toEqual([
      'grafico.png',
      'arquivos/b.png',
    ]);
    imgs.forEach(i => expect(i.hasAttribute('src')).toBe(false));
  });

  it('esquema de script em imagem não vira src', () => {
    const d = new DOMParser().parseFromString(
      html('![x](javascript:alert(1))'),
      'text/html'
    );
    expect(d.querySelectorAll('[src],[href]')).toHaveLength(0);
  });
});

describe('markdown: sanitização', () => {
  const doc = out => new DOMParser().parseFromString(out, 'text/html');

  it('remove script e HTML cru (markdown-it com html desligado)', () => {
    const out = html(
      'oi <script>alert(1)</script> <img src=x onerror="alert(1)"> <iframe src="//x"></iframe>'
    );
    const d = doc(out);
    expect(d.querySelector('script')).toBeNull();
    expect(d.querySelector('iframe')).toBeNull();
    expect(d.querySelector('img')).toBeNull();
    expect(
      [...d.querySelectorAll('*')].some(el =>
        el.getAttributeNames().some(n => n.startsWith('on'))
      )
    ).toBe(false);
  });

  it('o sanitizador remove atributos e tags perigosos mesmo se o HTML passar', () => {
    const out = r.sanitize(
      '<p onclick="x()" style="color:red">a</p><script>1</script>' +
        '<a href="javascript:alert(1)">b</a><form action="/x"><input></form>' +
        '<svg onload="x()"><circle/></svg><img src="https://a/b.png" onerror="x()">'
    );
    expect(out).not.toMatch(
      /onclick|style=|<script|javascript:|<form|<input|<svg|onerror|onload/i
    );
    expect(out).toContain('<p>a</p>');
  });

  it('data-* desconhecidos são removidos; só os do renderizador ficam', () => {
    const out = r.sanitize('<p data-x="1" data-copy-code="1">a</p>');
    expect(out).not.toContain('data-x');
    expect(out).toContain('data-copy-code');
  });
});

describe('markdown: streaming sem piscar', () => {
  it('blocos anteriores mantêm exatamente a mesma string enquanto o último cresce', () => {
    const base = '# Plano\n\nPrimeiro parágrafo.\n\n- a\n- b\n\n';
    const a = r.renderBlocks(`${base}Segundo par`);
    const b = r.renderBlocks(
      `${base}Segundo parágrafo completo com **negrito**`
    );
    expect(a.length).toBe(b.length);
    expect(a.slice(0, -1)).toEqual(b.slice(0, -1));
    expect(a[a.length - 1]).not.toEqual(b[b.length - 1]);
  });

  it('tabela e código incompletos no meio do stream não quebram', () => {
    expect(() => html('| a | b |\n|---|')).not.toThrow();
    const out = html('```py\nprint(1)');
    expect(out).toContain('rt-md-code');
    expect(out).toContain('print(1)');
  });

  it('lista com itens separados por linha em branco continua uma lista só', () => {
    const blocks = r.renderBlocks('1. um\n\n2. dois\n\n3. tres');
    expect(blocks).toHaveLength(1);
    expect(blocks[0]).toContain('<li>');
  });

  it('texto vazio não gera blocos', () => {
    expect(r.renderBlocks('')).toEqual([]);
    expect(r.renderBlocks('  \n ')).toEqual([]);
  });
});

describe('whatsapp e text', () => {
  it('whatsapp: *negrito*, _itálico_, ~tachado~ e mono; sem interpretar markdown', () => {
    const out = html(
      '*Pedido* confirmado, _obrigado_ ~erro~ ```x=1```\n# não é título\n| a | b |',
      {
        format: 'whatsapp',
      }
    );
    expect(out).toContain('<strong>Pedido</strong>');
    expect(out).toContain('<em>obrigado</em>');
    expect(out).toContain('<del>erro</del>');
    expect(out).toContain('x=1</code>');
    expect(out).toContain('# não é título');
    expect(out).not.toContain('<h1>');
    expect(out).not.toContain('<table>');
  });

  it('whatsapp: não formata dentro de palavras nem multiplicações', () => {
    const out = whatsappToHtml('snake_case_name e 2*3*4 e a * b * c');
    expect(out).not.toContain('<em>');
    expect(out).not.toContain('<strong>');
  });

  it('whatsapp: HTML cru é escapado', () => {
    const out = html('*oi* <script>alert(1)</script> <b>x</b>', {
      format: 'whatsapp',
    });
    expect(out).toContain('<strong>oi</strong>');
    expect(out).toContain('&lt;script&gt;');
    expect(out).not.toContain('<script');
    expect(out).not.toContain('<b>');
  });

  it('text: nada é interpretado', () => {
    const out = html('**nao** *negrito* # titulo [l](http://x) <b>y</b>', {
      format: 'text',
    });
    expect(out).toBe(
      '<p>**nao** *negrito* # titulo [l](http://x) &lt;b&gt;y&lt;/b&gt;</p>'
    );
  });
});
