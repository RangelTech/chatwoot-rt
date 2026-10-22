import { mount, flushPromises } from '@vue/test-utils';
import ServicesSection from './ServicesSection.vue';
import ptBR from '../../../../i18n/locale/pt_BR/ragent.json';

const mockAlert = vi.fn();
vi.mock('dashboard/composables', () => ({ useAlert: m => mockAlert(m) }));

const lookup = (obj, path) =>
  path.split('.').reduce((acc, k) => (acc ? acc[k] : undefined), obj);
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params = {}) => {
      const raw = key.split('.').reduce(
        (acc, k) => (acc ? acc[k] : undefined),
        window.__ragent
      );
      return String(raw ?? key).replace(/\{(\w+)\}/g, (_, n) => params[n]);
    },
    te: () => true,
  }),
}));

const Btn = {
  props: ['label'],
  emits: ['click'],
  template: '<button @click="$emit(\'click\')">{{ label }}</button>',
};

const RUNNING = {
  ambiente: 'ativo',
  servicos: [
    {
      nome: 'web',
      estado: 'rodando',
      uptime_s: 3900,
      cpu_pct: 1.5,
      mem_mb: 30,
      portas: [8000],
      url_publica: 'https://web-t1.apps.exemplo.net',
    },
    { nome: 'worker', estado: 'parado', uptime_s: 0, portas: [] },
  ],
  soltos: [
    { pid: 9, comando: 'python3', argumentos: 'python3 x.py', uptime_s: 5, portas: [] },
  ],
  conteineres: [],
};

const setup = async ({ scopes, services = RUNNING } = {}) => {
  window.__ragent = ptBR;
  const axios = {
    get: vi.fn(url => {
      if (url.endsWith('/rt_ai/me')) return Promise.resolve({ data: { scopes } });
      if (url.endsWith('/logs')) {
        return Promise.resolve({ data: { log: 'linha 1\nlinha 2' } });
      }
      return Promise.resolve({ data: services });
    }),
    post: vi.fn(() => Promise.resolve({ data: { ok: true } })),
  };
  window.axios = axios;
  const wrapper = mount(ServicesSection, {
    props: { accountId: 7 },
    global: { stubs: { Button: Btn } },
  });
  await flushPromises();
  return { wrapper, axios };
};

describe('ServicesSection', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mockAlert.mockClear();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('lists services with state, uptime, port and public address', async () => {
    const { wrapper } = await setup({ scopes: ['ai.environment.view'] });
    const rows = wrapper.findAll('[data-testid="service-row"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].text()).toContain('web');
    expect(rows[0].text()).toContain('Rodando');
    expect(rows[0].text()).toContain('1 h 5 min');
    expect(rows[0].text()).toContain('8000');
    expect(rows[0].find('a').attributes('href')).toBe('https://web-t1.apps.exemplo.net');
    expect(rows[1].text()).toContain('Parado');
    expect(wrapper.find('[data-testid="loose-row"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('não voltam após reiniciar o ambiente');
  });

  it('hides every action for users without ai.environment.manage', async () => {
    const { wrapper } = await setup({ scopes: ['ai.environment.view'] });
    expect(wrapper.find('[data-testid="service-stop"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="service-logs"]').exists()).toBe(false);
  });

  it('asks for confirmation before stopping and posts only after yes', async () => {
    const { wrapper, axios } = await setup({
      scopes: ['ai.environment.view', 'ai.environment.manage'],
    });
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    await wrapper.find('[data-testid="service-stop"]').trigger('click');
    await flushPromises();
    expect(confirm).toHaveBeenCalled();
    expect(axios.post).not.toHaveBeenCalled();
    confirm.mockReturnValue(true);
    await wrapper.find('[data-testid="service-stop"]').trigger('click');
    await flushPromises();
    expect(axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/7/rt_ai/resources/environment_services/web/actions/stop'
    );
    confirm.mockRestore();
  });

  it('starts a stopped service without confirmation and opens the logs', async () => {
    const { wrapper, axios } = await setup({
      scopes: ['ai.environment.manage'],
    });
    await wrapper.find('[data-testid="service-start"]').trigger('click');
    await flushPromises();
    expect(axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/7/rt_ai/resources/environment_services/worker/actions/start'
    );
    await wrapper.find('[data-testid="service-logs"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="service-log-panel"]').text()).toContain('linha 2');
  });

  it('refreshes on a timer and by button', async () => {
    const { wrapper, axios } = await setup({ scopes: [] });
    const count = () =>
      axios.get.mock.calls.filter(c => c[0].endsWith('/environment_services')).length;
    expect(count()).toBe(1);
    vi.advanceTimersByTime(15000);
    await flushPromises();
    expect(count()).toBe(2);
    await wrapper.find('[data-testid="services-refresh"]').trigger('click');
    await flushPromises();
    expect(count()).toBe(3);
    wrapper.unmount();
    vi.advanceTimersByTime(60000);
    expect(count()).toBe(3);
  });

  it('shows a calm notice (no error) when the environment is stopped', async () => {
    const { wrapper } = await setup({
      scopes: ['ai.environment.manage'],
      services: { ambiente: 'parado', servicos: [], soltos: [] },
    });
    expect(wrapper.find('[data-testid="services-notice"]').text()).toContain('Ambiente parado');
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="service-row"]').exists()).toBe(false);
  });

  it('renders the empty state with zero services', async () => {
    const { wrapper } = await setup({
      scopes: [],
      services: { ambiente: 'ativo', servicos: [], soltos: [] },
    });
    expect(wrapper.find('[data-testid="services-empty"]').exists()).toBe(true);
  });

  it('never shows internal vocabulary in the screen texts', () => {
    const text = JSON.stringify(lookup(ptBR, 'RAGENT.RES.ENV.SERVICES')).toLowerCase();
    ['kernel', 'hermes', 'harness'].forEach(w => expect(text).not.toContain(w));
  });
});
