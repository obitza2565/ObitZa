window.OBZ_CONFIG = {
  // HTTPS reverse proxy (nginx + Let's Encrypt) in front of the Hetzner backend.
  // Must stay https:// — the site is served over HTTPS and browsers block
  // mixed-content requests to a plain http:// API.
  apiBase: 'https://api.obzexchange.com',

  // WalletConnect v2 project ID (public identifier, NOT a secret — safe to
  // commit). Create a free one at https://cloud.walletconnect.com and paste
  // it here to enable "Connect via Trust Wallet / WalletConnect (QR code)".
  walletConnectProjectId: '3a2cc7a481247a0f965c764d45ef215e',

  // ── Chain config — OBZ lives on BNB Smart Chain MAINNET ──────────────────
  chainId: 56,
  chainName: 'BNB Smart Chain',
  rpcUrl: 'https://bsc-dataseed.binance.org/',
  explorer: 'https://bscscan.com',
  nativeCurrency: { name: 'BNB', symbol: 'BNB', decimals: 18 },

  // ── Tokens (mainnet) ─────────────────────────────────────────────────────
  obzToken: '0x5e1834c8D1B50F0B9e13712CD9ed1d90892a9Bf7',
  usdtToken: '0x55d398326f99059fF775485246999027B3197955',
  wbnb: '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c',
  pancakeRouter: '0x10ED43C718714eb63d5aA57B78B54704E256024E',

  // ── OBZ Fee Router (1% platform fee + 10 USDT/day per-wallet limit) ──────
  // Deployed on BSC mainnet: scripts/deploy-fee-router.js
  // https://bscscan.com/address/0xDB9d0B031631F5E38652053aCCbB5E8b5c4A3B28
  feeRouter: '0xDB9d0B031631F5E38652053aCCbB5E8b5c4A3B28',
  feeWallet: '0x41a0096ef2E784d574156Ddec32853B666C6dbE1',
  swapDailyLimitUsdt: 10,
  swapFeeBps: 100, // 1%
};
