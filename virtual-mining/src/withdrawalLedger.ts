import { randomUUID } from "crypto";
import { WithdrawalRequest, WithdrawalStatus } from "./types";

/** In-memory ledger of withdrawal requests awaiting or past admin review. */
export class WithdrawalLedger {
  private requests = new Map<string, WithdrawalRequest>();

  create(userId: string, walletAddress: string, amountObz: number, amountUsdt: number): WithdrawalRequest {
    const request: WithdrawalRequest = {
      id: randomUUID(),
      userId,
      walletAddress,
      amountObz,
      amountUsdt,
      status: "PENDING",
      createdAt: Date.now(),
    };
    this.requests.set(request.id, request);
    return request;
  }

  get(id: string): WithdrawalRequest | undefined {
    return this.requests.get(id);
  }

  list(status?: WithdrawalStatus): WithdrawalRequest[] {
    const all = Array.from(this.requests.values()).sort((a, b) => b.createdAt - a.createdAt);
    return status ? all.filter((r) => r.status === status) : all;
  }

  markDecided(id: string, status: WithdrawalStatus, patch: Partial<WithdrawalRequest> = {}): WithdrawalRequest {
    const request = this.requests.get(id);
    if (!request) throw new Error("withdrawal request not found");
    Object.assign(request, patch, { status, decidedAt: Date.now() });
    return request;
  }
}

export const withdrawalLedger = new WithdrawalLedger();
