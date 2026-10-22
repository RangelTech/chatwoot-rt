import { mount, flushPromises } from '@vue/test-utils';
import FieldsStep from '../FieldsStep.vue';
import QrStep from '../QrStep.vue';
import ErrorNotice from '../ErrorNotice.vue';
import ConnectionPanel from '../ConnectionPanel.vue';
import ConnectChannelWizard from '../ConnectChannelWizard.vue';
import { errorI18nKey, parseHttpError } from '../errorCodes';
import { ERROR_CODES } from '../constants';
import channelApi from 'dashboard/api/channelConnections';
import enChannelConnect from 'dashboard/i18n/locale/en/channelConnect.json';
import ptChannelConnect from 'dashboard/i18n/locale/pt_BR/channelConnect.json';

const PASSWORD = 'S3nh4-Super-Secreta';
const $t = (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key);

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: k => k, te: () => false, locale: { value: 'en' } }),
}));
vi.mock('qrcode', () => ({
  default: {
    toDataURL: vi.fn(async text => `data:image/png;base64,${btoa(text)}`),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: { value: 1 } }),
}));
const dispatch = vi.fn();
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: () => ({ value: [] }),
}));
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));
vi.mock('dashboard/api/channelConnections', () => ({
  default: {
    start: vi.fn(),
    step: vi.fn(),
    status: vi.fn(),
    cancel: vi.fn(),
    disconnect: vi.fn(),
    revoke: vi.fn(),
    reauth: vi.fn(),
    finalize: vi.fn(),
  },
}));

const stubs = {
  NextButton: {
    props: ['label', 'disabled'],
    emits: ['click'],
    template:
      '<button :disabled="disabled" :data-label="label" @click="$emit(\'click\')">{{ label }}</button>',
  },
  Icon: true,
  Spinner: true,
};
const global = { mocks: { $t }, stubs };

const credStep = {
  step_id: 's1',
  kind: 'credentials',
  fields: [
    { id: 'username', type: 'username', label_key: 'L.USER' },
    { id: 'password', type: 'password', label_key: 'L.PASS', secret: true },
  ],
};

describe('FieldsStep', () => {
  it('mascara a senha, desliga autocomplete e emite os dados', async () => {
    const wrapper = mount(FieldsStep, { props: { step: credStep }, global });
    const pass = wrapper.find('[data-field="password"]');
    expect(pass.attributes('type')).toBe('password');
    expect(pass.attributes('autocomplete')).toBe('off');
    expect(wrapper.find('form').attributes('autocomplete')).toBe('off');

    await wrapper.find('[data-field="username"]').setValue(' lucas ');
    await pass.setValue(PASSWORD);
    await wrapper.find('form').trigger('submit');
    expect(wrapper.emitted('submit')[0][0]).toEqual({
      username: 'lucas',
      password: PASSWORD,
    });
  });

  it('limpa a senha do estado local e do DOM apos o envio', async () => {
    const wrapper = mount(FieldsStep, { props: { step: credStep }, global });
    await wrapper.find('[data-field="username"]').setValue('u');
    await wrapper.find('[data-field="password"]').setValue(PASSWORD);
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(wrapper.find('[data-field="password"]').element.value).toBe('');
    expect(wrapper.html()).not.toContain(PASSWORD);
  });

  it('nao envia com campo vazio nem bloqueado', async () => {
    const wrapper = mount(FieldsStep, { props: { step: credStep }, global });
    await wrapper.find('form').trigger('submit');
    expect(wrapper.emitted('submit')).toBeUndefined();
  });

  it('nao grava senha em localStorage/sessionStorage', async () => {
    localStorage.clear();
    sessionStorage.clear();
    const wrapper = mount(FieldsStep, { props: { step: credStep }, global });
    await wrapper.find('[data-field="username"]').setValue('u');
    await wrapper.find('[data-field="password"]').setValue(PASSWORD);
    await wrapper.find('form').trigger('submit');
    const dump = JSON.stringify({ ...localStorage, ...sessionStorage });
    expect(dump).not.toContain(PASSWORD);
  });
});

describe('QrStep', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval', 'Date'] });
    vi.setSystemTime(new Date('2026-10-20T12:00:00Z'));
  });
  afterEach(() => vi.useRealTimers());

  const qrStep = (data, exp, refresh = 10) => ({
    step_id: 'q',
    kind: 'qr',
    qr: { data, expires_at: exp, refresh_after_s: refresh },
  });

  it('renderiza o QR, conta regressivamente e redesenha quando renova', async () => {
    const wrapper = mount(QrStep, {
      props: {
        step: qrStep('QR-1', '2026-10-20T12:00:30Z', 30),
        provider: 'tiktok',
      },
      global,
    });
    await flushPromises();
    const first = wrapper.find('[data-test="qr-image"]').attributes('src');
    expect(first).toMatch(/^data:image\/png/);
    expect(wrapper.find('[data-test="qr-countdown"]').text()).toContain(
      '"seconds":30'
    );
    vi.advanceTimersByTime(5000);
    await flushPromises();
    expect(wrapper.find('[data-test="qr-countdown"]').text()).toContain(
      '"seconds":25'
    );

    await wrapper.setProps({
      step: qrStep('QR-2-OUTRO', '2026-10-20T12:01:00Z'),
    });
    await flushPromises();
    const second = wrapper.find('[data-test="qr-image"]').attributes('src');
    expect(second).not.toBe(first);
    expect(wrapper.text()).toContain('CHANNEL_CONNECT.STEPS.QR_HELP_TIKTOK');
  });

  it('contagem independe do relogio do servidor (usa refresh_after_s)', async () => {
    // servidor 9 min adiantado: expires_at muito no futuro; a tela mostra o tempo relativo
    const wrapper = mount(QrStep, {
      props: {
        step: qrStep('QR-SKEW', '2026-10-20T12:09:20Z', 20),
        provider: 'whatsapp',
      },
      global,
    });
    await flushPromises();
    expect(wrapper.find('[data-test="qr-countdown"]').text()).toContain(
      '"seconds":20'
    );
  });

  it('mostra instrucao do WhatsApp e o codigo de pareamento', () => {
    const wa = mount(QrStep, {
      props: {
        step: qrStep('QR', '2026-10-20T12:00:30Z'),
        provider: 'whatsapp',
      },
      global,
    });
    expect(wa.text()).toContain('CHANNEL_CONNECT.STEPS.QR_HELP_WHATSAPP');
    const pairing = mount(QrStep, {
      props: {
        step: { step_id: 'p', kind: 'pairing_code', pairing_code: 'ABCD-1234' },
        provider: 'whatsapp',
      },
      global,
    });
    expect(pairing.find('[data-test="pairing-code"]').text()).toBe('ABCD-1234');
  });
});

describe('ErrorNotice e codigos de erro', () => {
  it('cada error_code do contrato tem mensagem em EN e PT-BR', () => {
    ERROR_CODES.forEach(code => {
      const key = errorI18nKey(code).split('.').pop();
      expect(enChannelConnect.CHANNEL_CONNECT.ERRORS[key]).toBeTruthy();
      expect(ptChannelConnect.CHANNEL_CONNECT.ERRORS[key]).toBeTruthy();
    });
  });

  it('codigo desconhecido cai na mensagem generica', () => {
    expect(errorI18nKey('zzz')).toBe('CHANNEL_CONNECT.ERRORS.GENERIC');
  });

  it('EN e PT-BR tem exatamente as mesmas chaves', () => {
    const flat = (o, p = '') =>
      Object.entries(o).flatMap(([k, v]) =>
        typeof v === 'object' ? flat(v, `${p}${k}.`) : [`${p}${k}`]
      );
    expect(flat(ptChannelConnect).sort()).toEqual(
      flat(enChannelConnect).sort()
    );
  });

  it('mostra attempts_left', () => {
    const wrapper = mount(ErrorNotice, {
      props: { code: 'wrong_password', attemptsLeft: 2 },
      global,
    });
    expect(wrapper.text()).toContain('CHANNEL_CONNECT.ERRORS.WRONG_PASSWORD');
    expect(wrapper.text()).toContain('"count":2');
  });

  it('429 vira too_many_attempts', () => {
    expect(parseHttpError({ response: { status: 429, data: {} } }).code).toBe(
      'too_many_attempts'
    );
  });
});

describe('ConnectChannelWizard', () => {
  beforeEach(() => vi.clearAllMocks());

  it('oficial x experimental: experimental exige consentimento', async () => {
    const wrapper = mount(ConnectChannelWizard, {
      props: { provider: 'instagram' },
      global,
    });
    expect(wrapper.find('[data-test="mode-official"]').exists()).toBe(true);
    await wrapper.find('[data-test="mode-experimental"]').trigger('click');
    expect(wrapper.find('[data-test="risk-box"]').text()).toContain(
      'CHANNEL_CONNECT.INFO.RISK_2FA'
    );
    const btn = wrapper.find('[data-test="consent-continue"]');
    expect(btn.attributes('disabled')).toBeDefined();
    await wrapper.find('[data-test="consent-checkbox"]').setValue(true);
    channelApi.start.mockResolvedValue({
      data: { connection: { id: 'c1', state: 'pending_auth' }, step: credStep },
    });
    await wrapper.find('[data-test="consent-continue"]').trigger('click');
    await flushPromises();
    expect(channelApi.start).toHaveBeenCalledWith(
      expect.objectContaining({ provider: 'instagram', consent: true })
    );
    expect(wrapper.find('[data-test="fields-step"]').exists()).toBe(true);
  });

  it('a senha digitada nao aparece em props, DOM, chamadas de store nem estado do assistente', async () => {
    const wrapper = mount(ConnectChannelWizard, {
      props: { provider: 'instagram' },
      global,
    });
    await wrapper.find('[data-test="mode-experimental"]').trigger('click');
    await wrapper.find('[data-test="consent-checkbox"]').setValue(true);
    channelApi.start.mockResolvedValue({
      data: { connection: { id: 'c1', state: 'pending_auth' }, step: credStep },
    });
    await wrapper.find('[data-test="consent-continue"]').trigger('click');
    await flushPromises();

    channelApi.step.mockResolvedValue({
      data: {
        connection: { id: 'c1', state: 'pending_auth' },
        step: { ...credStep, error_code: 'wrong_password', attempts_left: 2 },
      },
    });
    await wrapper.find('[data-field="username"]').setValue('lucas');
    await wrapper.find('[data-field="password"]').setValue(PASSWORD);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    // a senha so foi para o BFF
    expect(channelApi.step.mock.calls[0][1].data.password).toBe(PASSWORD);
    expect(JSON.stringify(dispatch.mock.calls)).not.toContain(PASSWORD);
    expect(wrapper.html()).not.toContain(PASSWORD);
    const { wizard } = wrapper.vm;
    const state = JSON.stringify({
      p: wizard.phase.value,
      c: wizard.connection.value,
      s: wizard.step.value,
      e: wizard.error.value,
    });
    expect(state).not.toContain(PASSWORD);
    expect(JSON.stringify({ ...localStorage })).not.toContain(PASSWORD);
    // erro em portugues claro com tentativas restantes, sem retry automatico
    expect(wrapper.text()).toContain('CHANNEL_CONNECT.ERRORS.WRONG_PASSWORD');
    expect(channelApi.step).toHaveBeenCalledTimes(1);
  });

  it('nao tem nenhum passo ou texto de copiar cookie', () => {
    const wrapper = mount(ConnectChannelWizard, {
      props: { provider: 'tiktok' },
      global,
    });
    expect(wrapper.html().toLowerCase()).not.toContain('cookie');
    expect(JSON.stringify(enChannelConnect).toLowerCase()).not.toContain(
      'cookie'
    );
    expect(JSON.stringify(ptChannelConnect).toLowerCase()).not.toContain(
      'cookie'
    );
  });
});

describe('ConnectionPanel', () => {
  const inbox = { id: 5, channel_type: 'Channel::InstagramUnofficial' };
  const base = {
    id: 'c1',
    provider: 'instagram',
    state: 'reauth_required',
    last_activity_at: '2026-10-20T10:00:00Z',
    last_error_code: 'checkpoint_required',
    connector_version: 'ig-v26.10',
  };

  it('mostra estado, ultimo erro, versao e oferece reconectar', () => {
    const wrapper = mount(ConnectionPanel, {
      props: { inbox, connection: base },
      global,
    });
    expect(wrapper.find('[data-test="panel-state"]').text()).toContain(
      'REAUTH_REQUIRED'
    );
    expect(wrapper.find('[data-test="panel-error"]').text()).toContain(
      'CHECKPOINT_REQUIRED'
    );
    expect(wrapper.find('[data-test="panel-version"]').text()).toBe(
      'ig-v26.10'
    );
    expect(wrapper.find('[data-test="panel-reconnect"]').exists()).toBe(true);
  });

  it('desconectar pede confirmacao antes de chamar o BFF', async () => {
    channelApi.disconnect.mockResolvedValue({});
    const wrapper = mount(ConnectionPanel, {
      props: { inbox, connection: { ...base, state: 'connected' } },
      global,
    });
    expect(wrapper.find('[data-test="panel-reconnect"]').exists()).toBe(false);
    await wrapper.find('[data-test="panel-disconnect"]').trigger('click');
    expect(channelApi.disconnect).not.toHaveBeenCalled();
    expect(wrapper.find('[data-test="confirm-box"]').exists()).toBe(true);
    await wrapper.find('[data-test="confirm-yes"]').trigger('click');
    await flushPromises();
    expect(channelApi.disconnect).toHaveBeenCalledWith('c1');
    expect(wrapper.emitted('changed')).toBeTruthy();
  });

  it('revogar tambem pede confirmacao', async () => {
    channelApi.revoke.mockResolvedValue({});
    const wrapper = mount(ConnectionPanel, {
      props: { inbox, connection: { ...base, state: 'connected' } },
      global,
    });
    await wrapper.find('[data-test="panel-revoke"]').trigger('click');
    expect(channelApi.revoke).not.toHaveBeenCalled();
    await wrapper.find('[data-test="confirm-yes"]').trigger('click');
    await flushPromises();
    expect(channelApi.revoke).toHaveBeenCalledWith('c1');
  });
});

describe('FieldsStep - passos genericos do provedor', () => {
  it('escolha: select com padrao, emite a opcao e mostra a mensagem do provedor', async () => {
    const step = {
      step_id: 'x.dialog',
      kind: 'choice',
      instructions: "Can't find account",
      fields: [
        {
          id: 'dialog_action',
          type: 'select',
          label: 'Continue login',
          options: ['Sign up', 'Try again'],
          default: 'Try again',
        },
      ],
    };
    const wrapper = mount(FieldsStep, { props: { step }, global });
    expect(wrapper.find('[data-test="provider-message"]').text()).toContain(
      "Can't find account"
    );
    const sel = wrapper.find('[data-field="dialog_action"]');
    expect(sel.element.value).toBe('Try again');
    await wrapper.find('form').trigger('submit');
    expect(wrapper.emitted('submit')[0][0]).toEqual({
      dialog_action: 'Try again',
    });
  });

  it('captcha: mostra imagem e audio e envia o texto', async () => {
    const step = {
      step_id: 'x.captcha',
      kind: 'captcha',
      instructions: 'Type the characters',
      attachments: [
        { kind: 'image', mime: 'image/png', data: 'AAAA' },
        { kind: 'audio', mime: 'audio/ogg', data: 'BBBB' },
      ],
      fields: [{ id: 'captcha_code', type: 'captcha_code', label: 'Captcha' }],
    };
    const wrapper = mount(FieldsStep, { props: { step }, global });
    expect(wrapper.find('img').attributes('src')).toBe(
      'data:image/png;base64,AAAA'
    );
    expect(wrapper.find('audio').attributes('src')).toBe(
      'data:audio/ogg;base64,BBBB'
    );
    await wrapper.find('[data-field="captcha_code"]').setValue('abcd');
    await wrapper.find('form').trigger('submit');
    expect(wrapper.emitted('submit')[0][0]).toEqual({ captcha_code: 'abcd' });
  });
});
