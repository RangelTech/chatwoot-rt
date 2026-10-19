import Auth from '../api/auth';

// Senha provisória (spec 10, U-1c): o back responde 403 `must_change_password`
// até a pessoa trocar a senha; levamos direto à tela de perfil.
const redirectToPasswordChange = error => {
  const isPending = error?.response?.data?.code === 'must_change_password';
  const accountId = window.location.pathname.match(/accounts\/(\d+)/)?.[1];
  if (isPending && accountId && !window.location.pathname.includes('/profile')) {
    window.location.assign(`/app/accounts/${accountId}/profile/settings`);
  }
};

const parseErrorCode = error => {
  redirectToPasswordChange(error);
  return Promise.reject(error);
};

export default axios => {
  const { apiHost = '' } = window.chatwootConfig || {};
  const wootApi = axios.create({ baseURL: `${apiHost}/` });
  // Add Auth Headers to requests if logged in
  if (Auth.hasAuthCookie()) {
    const {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    } = Auth.getAuthData();
    Object.assign(wootApi.defaults.headers.common, {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    });
  }
  // Response parsing interceptor
  wootApi.interceptors.response.use(
    response => response,
    error => parseErrorCode(error)
  );
  return wootApi;
};
