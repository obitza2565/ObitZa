export interface MiningSession {
  userId: string;
  walletAddress: string;
  ratePerHour: number;
  running: boolean;
  claimableObz: number;
  totalMinedObz: number;
  pendingWithdrawal: boolean;
  startedAt: number;
  lastTickAt: number;
}

export interface MiningStatus {
  userId: string;
  walletAddress: string;
  running: boolean;
  ratePerHour: number;
  claimableObz: number;
  claimableUsdt: number;
  totalMinedObz: number;
}

export interface PoolStatus {
  dateKey: string;
  dailyCapObz: number;
  totalMinedTodayObz: number;
  remainingObz: number;
  obzPriceUsdt: number;
  activeMiners: number;
}

export interface PayoutResult {
  txHash: string;
  amountObz: number;
  toAddress: string;
}

export type WithdrawalStatus = "PENDING" | "APPROVED" | "REJECTED" | "PAID" | "FAILED";

export interface WithdrawalRequest {
  id: string;
  userId: string;
  walletAddress: string;
  amountObz: number;
  amountUsdt: number;
  status: WithdrawalStatus;
  createdAt: number;
  decidedAt?: number;
  txHash?: string;
  note?: string;
}
