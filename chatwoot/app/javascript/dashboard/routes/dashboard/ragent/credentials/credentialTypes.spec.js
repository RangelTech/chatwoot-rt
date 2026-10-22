import {
  CREDENTIAL_TYPES,
  buildPayload,
  initialForm,
  missingFields,
  typeOf,
  visibleFields,
} from './credentialTypes';

describe('credentialTypes', () => {
  it('has a form for every kind of credential the agent can use', () => {
    expect(CREDENTIAL_TYPES.map(t => t.key)).toEqual([
      'secret',
      'database',
      'ssh',
      'gcp',
      'aws',
      'azure',
      'email',
      'payment',
      'google',
      'microsoft',
    ]);
  });

  it('only asks SQLite for the file path', () => {
    const type = typeOf('database');
    const keys = form => visibleFields(type, form).map(f => f.key);
    expect(keys({ db_kind: 'sqlite' })).toEqual(['db_kind', 'name', 'path']);
    expect(keys({ db_kind: 'postgres' })).toContain('host');
    expect(keys({ db_kind: 'postgres' })).not.toContain('path');
  });

  it('builds the create payload with defaults and without empty fields', () => {
    const type = typeOf('ssh');
    const form = {
      ...initialForm(type),
      name: 'do servidor',
      host: '10.0.0.1',
      user: 'root',
      value: 'KEY',
    };
    expect(buildPayload(type, form)).toEqual({
      type: 'ssh',
      name: 'do servidor',
      host: '10.0.0.1',
      port: 22,
      user: 'root',
      value: 'KEY',
    });
  });

  it('keeps the current secret when replacing with a blank value', () => {
    const type = typeOf('database');
    const item = {
      name: 'loja',
      info: {
        db_kind: 'postgres',
        host: 'h',
        port: 5432,
        database: 'd',
        user: 'u',
        has_password: true,
      },
    };
    const form = initialForm(type, item);
    expect(form.password).toBe('');
    expect(form.host).toBe('h');
    const body = buildPayload(type, form, { replace: true });
    expect(body).not.toHaveProperty('password');
    expect(body).not.toHaveProperty('name');
    expect(body).not.toHaveProperty('db_kind');
    expect(body).toMatchObject({ host: 'h', port: 5432, user: 'u' });
    expect(missingFields(type, form, { replace: true })).toEqual([]);
  });

  it('flags missing required fields on create but not optional ones', () => {
    const type = typeOf('payment');
    expect(missingFields(type, initialForm(type))).toEqual(['access_token']);
    const secretType = typeOf('secret');
    expect(missingFields(secretType, initialForm(secretType))).toEqual([
      'name',
      'value',
    ]);
  });
});
