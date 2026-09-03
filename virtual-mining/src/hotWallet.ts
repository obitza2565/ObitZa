import { ethers } from "ethers";
import { config } from "./config";
import { PayoutResult } from "./types";

const ERC20_ABI = [
  "function transfer(address to, uint256 amount) returns (bool)",
  "function balanceOf(address owner) view returns (uint256)",
  "function decimals() view returns (uint8)",
];

/**
 * Hot wallet payout backend for BNB Chain. Connects only to an external
 * public RPC endpoint — this process never runs a blockchain node itself.
 */
class HotWallet {
  private provider: ethers.JsonRpcProvider | null = null;
  private wallet: ethers.Wallet | null = null;
  private token: ethers.Contract | null = null;

  /** Lazily builds the signer so the mining simulator can run without payout credentials. */
  private ensureReady(): { wallet: ethers.Wallet; token: ethers.Contract } {
    if (!config.hotWalletPrivateKey) {
      throw new Error("HOT_WALLET_PRIVATE_KEY is not configured");
    }
    if (!ethers.isAddress(config.obzTokenAddress)) {
      throw new Error("OBZ_TOKEN_ADDRESS is not a valid address");
    }
    if (!this.provider) {
      this.provider = new ethers.JsonRpcProvider(config.bscRpcUrl);
    }
    if (!this.wallet) {
      this.wallet = new ethers.Wallet(config.hotWalletPrivateKey, this.provider);
    }
    if (!this.token) {
      this.token = new ethers.Contract(config.obzTokenAddress, ERC20_ABI, this.wallet);
    }
    return { wallet: this.wallet, token: this.token };
  }

  async sendObzPayout(toAddress: string, amountObz: number): Promise<PayoutResult> {
    if (!ethers.isAddress(toAddress)) {
      throw new Error("invalid destination wallet address");
    }
    if (!(amountObz > 0)) {
      throw new Error("payout amount must be positive");
    }

    const { token } = this.ensureReady();
    const amountUnits = ethers.parseUnits(amountObz.toFixed(config.obzTokenDecimals), config.obzTokenDecimals);
    const tx = await token.transfer(toAddress, amountUnits);
    const receipt = await tx.wait(1);

    return {
      txHash: receipt?.hash ?? tx.hash,
      amountObz,
      toAddress,
    };
  }

  async getBalances(): Promise<{ address: string; bnb: string; obz: string }> {
    const { wallet, token } = this.ensureReady();
    const [bnbWei, obzUnits] = await Promise.all([
      this.provider!.getBalance(wallet.address),
      token.balanceOf(wallet.address) as Promise<bigint>,
    ]);
    return {
      address: wallet.address,
      bnb: ethers.formatEther(bnbWei),
      obz: ethers.formatUnits(obzUnits, config.obzTokenDecimals),
    };
  }
}

export const hotWallet = new HotWallet();
