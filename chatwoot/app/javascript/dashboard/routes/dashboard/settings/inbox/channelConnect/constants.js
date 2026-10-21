export const PROVIDERS = {
  instagram: {
    key: 'instagram',
    channelKey: 'instagram',
    icon: 'i-woot-instagram',
    login: 'password',
    officialSubPage: 'instagram',
    officialConfig: 'instagramAppId',
    channelType: 'Channel::InstagramUnofficial',
  },
  messenger: {
    key: 'messenger',
    channelKey: 'facebook',
    icon: 'i-woot-messenger',
    login: 'password',
    officialSubPage: 'facebook',
    officialConfig: 'fbAppId',
    channelType: 'Channel::MessengerUnofficial',
  },
  tiktok: {
    key: 'tiktok',
    channelKey: 'tiktok',
    icon: 'i-woot-tiktok',
    login: 'qr',
    officialSubPage: 'tiktok',
    officialConfig: 'tiktokAppId',
    channelType: 'Channel::TiktokUnofficial',
  },
  whatsapp: {
    key: 'whatsapp',
    channelKey: 'whatsapp',
    icon: 'i-woot-whatsapp',
    login: 'qr',
    officialSubPage: 'whatsapp',
    officialConfig: null,
    channelType: 'Channel::WhatsappUnofficial',
  },
};

// chave do catalogo (ChannelList) -> provider do assistente
export const CATALOG_KEY_TO_PROVIDER = Object.values(PROVIDERS).reduce(
  (acc, p) => ({ ...acc, [p.channelKey]: p.key }),
  {}
);

export const UNOFFICIAL_CHANNEL_TYPES = Object.values(PROVIDERS).map(
  p => p.channelType
);

export const STEP_KINDS = {
  CREDENTIALS: 'credentials',
  CODE_2FA: 'code_2fa',
  CAPTCHA: 'captcha',
  CHOICE: 'choice',
  AWAIT_APPROVAL: 'await_approval',
  QR: 'qr',
  PAIRING_CODE: 'pairing_code',
  SYNCING: 'syncing',
  COMPLETE: 'complete',
};

export const ERROR_CODES = [
  'wrong_password',
  'wrong_code',
  'wrong_captcha',
  'account_not_found',
  'login_rejected',
  'account_locked',
  'checkpoint_required',
  'timeout',
  'too_many_attempts',
  'provider_unavailable',
  'unsupported_step',
];

export const SYNC_WINDOWS_DAYS = [7, 30, 60];
