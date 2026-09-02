window.OBZ_CONFIG = {
  // HTTPS reverse proxy (nginx + Let's Encrypt) in front of the Hetzner backend.
  // Must stay https:// — the site is served over HTTPS and browsers block
  // mixed-content requests to a plain http:// API.
  apiBase: 'https://api.obzexchange.com',

  // WalletConnect v2 project ID (public identifier, NOT a secret — safe to
  // commit). Create a free one at https://cloud.walletconnect.com and paste
  // it here to enable "Connect via Trust Wallet / WalletConnect (QR code)".
  walletConnectProjectId: '3a2cc7a481247a0f965c764d45ef215e',
};
