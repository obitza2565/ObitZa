import { config } from "./config";
import { MiningSession, MiningStatus, PoolStatus } from "./types";

function utcDateKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/**
 * Timer-based virtual mining pool. No GPU/CPU work is performed — OBZ simply
 * accrues over wall-clock time at each session's rate, capped by a shared
 * daily budget so payouts stay predictable regardless of miner count.
 */
export class MiningPool {
  private sessions = new Map<string, MiningSession>();
  private dateKey = utcDateKey(new Date());
  private totalMinedTodayObz = 0;
  private timer: NodeJS.Timeout | null = null;

  start(): void {
    if (this.timer) return;
    this.timer = setInterval(() => this.tick(), config.tickIntervalMs);
  }

  stopEngine(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  private rolloverIfNewDay(): void {
    const today = utcDateKey(new Date());
    if (today !== this.dateKey) {
      this.dateKey = today;
      this.totalMinedTodayObz = 0;
    }
  }

  private tick(): void {
    this.rolloverIfNewDay();
    const now = Date.now();
    let remainingObz = Math.max(0, config.dailyMiningCapObz - this.totalMinedTodayObz);

    for (const session of this.sessions.values()) {
      if (!session.running || remainingObz <= 0) {
        session.lastTickAt = now;
        continue;
      }
      const dtSeconds = Math.max(0, (now - session.lastTickAt) / 1000);
      const potentialObz = (session.ratePerHour / 3600) * dtSeconds;
      // Later sessions in the same tick receive less once the shared daily
      // cap is exhausted — deterministic order is acceptable for a reference
      // implementation and keeps the payout budget hard-capped.
      const creditedObz = Math.min(potentialObz, remainingObz);

      session.claimableObz += creditedObz;
      session.totalMinedObz += creditedObz;
      session.lastTickAt = now;
      remainingObz -= creditedObz;
      this.totalMinedTodayObz += creditedObz;
    }
  }

  startMining(userId: string, walletAddress: string): MiningStatus {
    const now = Date.now();
    const existing = this.sessions.get(userId);
    if (existing) {
      existing.walletAddress = walletAddress;
      existing.running = true;
      existing.lastTickAt = now;
      existing.ratePerHour = config.defaultMiningRatePerHour;
      return this.toStatus(existing);
    }

    const session: MiningSession = {
      userId,
      walletAddress,
      // Reward rates are owned by the server. Never accept a client-supplied
      // rate: it would allow a browser request to bypass mining difficulty.
      ratePerHour: config.defaultMiningRatePerHour,
      running: true,
      claimableObz: 0,
      totalMinedObz: 0,
      pendingWithdrawal: false,
      startedAt: now,
      lastTickAt: now,
    };
    this.sessions.set(userId, session);
    return this.toStatus(session);
  }

  stopMining(userId: string): MiningStatus {
    const session = this.getSessionOrThrow(userId);
    session.running = false;
    return this.toStatus(session);
  }

  getStatus(userId: string): MiningStatus {
    return this.toStatus(this.getSessionOrThrow(userId));
  }

  getPoolStatus(): PoolStatus {
    this.rolloverIfNewDay();
    let activeMiners = 0;
    for (const session of this.sessions.values()) {
      if (session.running) activeMiners += 1;
    }
    return {
      dateKey: this.dateKey,
      dailyCapObz: config.dailyMiningCapObz,
      totalMinedTodayObz: this.totalMinedTodayObz,
      remainingObz: Math.max(0, config.dailyMiningCapObz - this.totalMinedTodayObz),
      obzPriceUsdt: config.obzPriceUsdt,
      activeMiners,
    };
  }

  /** Reserves `amount` OBZ from a user's claimable balance ahead of a payout attempt. */
  reserveForWithdrawal(userId: string, amount: number): MiningSession {
    const session = this.getSessionOrThrow(userId);
    if (session.pendingWithdrawal) {
      throw new Error("a withdrawal is already in progress for this user");
    }
    if (amount <= 0) {
      throw new Error("amount must be positive");
    }
    if (amount > session.claimableObz) {
      throw new Error("insufficient claimable balance");
    }
    session.claimableObz -= amount;
    session.pendingWithdrawal = true;
    return session;
  }

  /** Restores a reserved amount if the payout transaction failed to send. */
  refundWithdrawal(userId: string, amount: number): void {
    const session = this.sessions.get(userId);
    if (!session) return;
    session.claimableObz += amount;
    session.pendingWithdrawal = false;
  }

  /** Clears the pending flag once a payout transaction has been submitted. */
  commitWithdrawal(userId: string): void {
    const session = this.sessions.get(userId);
    if (!session) return;
    session.pendingWithdrawal = false;
  }

  private getSessionOrThrow(userId: string): MiningSession {
    const session = this.sessions.get(userId);
    if (!session) throw new Error("no mining session found for this user");
    return session;
  }

  private toStatus(session: MiningSession): MiningStatus {
    return {
      userId: session.userId,
      walletAddress: session.walletAddress,
      running: session.running,
      ratePerHour: session.ratePerHour,
      claimableObz: session.claimableObz,
      claimableUsdt: session.claimableObz * config.obzPriceUsdt,
      totalMinedObz: session.totalMinedObz,
    };
  }
}

export const miningPool = new MiningPool();
