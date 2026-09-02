window.OBZ_CONFIG = {
  // Hardcoded to the Hetzner backend (port 8080) so the frontend never falls
  // back to a broken/placeholder API base.
  apiBase: 'http://157.180.30.86:8080',

  // WalletConnect v2 project ID (public identifier, NOT a secret — safe to
  // commit). Create a free one at https://cloud.walletconnect.com and paste
  // it here to enable "Connect via Trust Wallet / WalletConnect (QR code)".
  walletConnectProjectId: '3a2cc7a481247a0f965c764d45ef215e',
};
