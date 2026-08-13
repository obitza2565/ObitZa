import sqlite3
import threading
import time
import hashlib
import secrets

class OBZDatabase:
    def __init__(self, db_path="obz_miner.db"):
        self.db_path = db_path
            self.lock = threading.RLock()
        self.init_db()

    def connect(self):
        return sqlite3.connect(self.db_path)

    def init_db(self):
        with self.lock, self.connect() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS network_config (
                    key TEXT PRIMARY KEY, value TEXT NOT NULL
                )
            """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS miners (
                    miner_id TEXT PRIMARY KEY, wallet_address TEXT NOT NULL,
                    last_seen INTEGER, banned INTEGER DEFAULT 0,
                    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS rewards (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    miner_id TEXT NOT NULL, nonce TEXT NOT NULL,
                    difficulty INTEGER NOT NULL, reward_amount REAL NOT NULL,
                    pool_fee_paid REAL NOT NULL, tx_signature TEXT,
                    status TEXT DEFAULT 'PENDING', timestamp INTEGER
                )
            """)
            cursor.execute("INSERT OR IGNORE INTO network_config (key, value) VALUES ('difficulty', '4')")
            cursor.execute("INSERT OR IGNORE INTO network_config (key, value) VALUES ('public_pool_fee_percent', '1.0')")
            cursor.execute("INSERT OR IGNORE INTO network_config (key, value) VALUES ('public_base_reward', '0.00025')")
            cursor.execute("INSERT OR IGNORE INTO network_config (key, value) VALUES ('public_hashrate_factor', '0.0000035')")
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS public_mining_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    miner_id TEXT NOT NULL,
                    wallet_address TEXT NOT NULL,
                    hashrate REAL NOT NULL,
                    gross_reward REAL NOT NULL,
                    pool_fee REAL NOT NULL,
                    net_reward REAL NOT NULL,
                    status TEXT DEFAULT 'SUCCESS',
                    timestamp INTEGER NOT NULL
                )
            """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS payout_requests (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    miner_id TEXT NOT NULL,
                    wallet_address TEXT NOT NULL,
                    amount REAL NOT NULL,
                    status TEXT NOT NULL DEFAULT 'PENDING',
                    tx_hash TEXT,
                    note TEXT,
                    requested_at INTEGER NOT NULL,
                    processed_at INTEGER
                )
            """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS payout_audit_logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    payout_request_id INTEGER NOT NULL,
                    miner_id TEXT NOT NULL,
                    actor TEXT,
                    from_status TEXT,
                    to_status TEXT NOT NULL,
                    tx_hash TEXT,
                    note TEXT,
                    changed_at INTEGER NOT NULL
                )
            """)
            cursor.execute("PRAGMA table_info(payout_audit_logs)")
            audit_columns = {row[1] for row in cursor.fetchall()}
            if "actor" not in audit_columns:
                cursor.execute("ALTER TABLE payout_audit_logs ADD COLUMN actor TEXT")
            conn.commit()

    def _get_float_config(self, key, fallback):
        with self.lock, self.connect() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT value FROM network_config WHERE key = ?", (key,))
            row = cursor.fetchone()
            if not row:
                return fallback
            try:
                return float(row[0])
            except (TypeError, ValueError):
                return fallback

    def get_difficulty(self):
        with self.lock, self.connect() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT value FROM network_config WHERE key = 'difficulty'")
            res = cursor.fetchone()
            return int(res) if res else 4

    def record_share_with_fee(self, miner_id, nonce, difficulty, net_reward, pool_fee):
        now = int(time.time())
        with self.lock, self.connect() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO rewards (miner_id, nonce, difficulty, reward_amount, pool_fee_paid, status, timestamp) 
                VALUES (?, ?, ?, ?, ?, 'SUCCESS', ?)
            """, (miner_id, nonce, difficulty, net_reward, pool_fee, now))
            cursor.execute("UPDATE miners SET last_seen = ? WHERE miner_id = ?", (now, miner_id))
            conn.commit()
            return cursor.lastrowid

    def upsert_public_miner(self, miner_id, wallet_address):
        now = int(time.time())
        with self.lock, self.connect() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                INSERT INTO miners (miner_id, wallet_address, last_seen, banned)
                VALUES (?, ?, ?, 0)
                ON CONFLICT(miner_id) DO UPDATE SET
                    wallet_address = excluded.wallet_address,
                    last_seen = excluded.last_seen,
                    banned = 0
                """,
                (miner_id, wallet_address, now),
            )
            conn.commit()

    def record_public_mining_tick(self, miner_id, wallet_address, hashrate):
        now = int(time.time())
        fee_percent = self._get_float_config('public_pool_fee_percent', 1.0)
        base_reward = self._get_float_config('public_base_reward', 0.00025)
        hashrate_factor = self._get_float_config('public_hashrate_factor', 0.0000035)

        bounded_hashrate = max(1.0, min(float(hashrate), 2000.0))
        gross_reward = base_reward + (bounded_hashrate * hashrate_factor)
        pool_fee = gross_reward * (fee_percent / 100.0)
        net_reward = gross_reward - pool_fee

        nonce_seed = f"{miner_id}:{wallet_address}:{now}:{bounded_hashrate:.4f}"
        nonce = hashlib.sha256(nonce_seed.encode()).hexdigest()[:24]

        with self.lock, self.connect() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                INSERT INTO public_mining_events
                (miner_id, wallet_address, hashrate, gross_reward, pool_fee, net_reward, status, timestamp)
                VALUES (?, ?, ?, ?, ?, ?, 'SUCCESS', ?)
                """,
                (miner_id, wallet_address, bounded_hashrate, gross_reward, pool_fee, net_reward, now),
            )
            cursor.execute(
                """
                INSERT INTO rewards (miner_id, nonce, difficulty, reward_amount, pool_fee_paid, status, timestamp)
                VALUES (?, ?, ?, ?, ?, 'SUCCESS', ?)
                """,
                (miner_id, nonce, self.get_difficulty(), net_reward, pool_fee, now),
            )
            cursor.execute("UPDATE miners SET last_seen = ? WHERE miner_id = ?", (now, miner_id))
            conn.commit()
            return {
                "hashrate": bounded_hashrate,
                "gross_reward": gross_reward,
                "pool_fee": pool_fee,
                "net_reward": net_reward,
                "timestamp": now,
            }

    def get_public_miner_snapshot(self, miner_id):
        day_start = int(time.time()) - 86400
        with self.lock, self.connect() as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()

            cursor.execute(
                "SELECT miner_id, wallet_address, last_seen FROM miners WHERE miner_id = ?",
                (miner_id,),
            )
            miner = cursor.fetchone()
            if not miner:
                return None

            cursor.execute(
                "SELECT COALESCE(SUM(net_reward),0), COALESCE(AVG(hashrate),0), COUNT(*) FROM public_mining_events WHERE miner_id = ?",
                (miner_id,),
            )
            total_reward, avg_hashrate, total_ticks = cursor.fetchone()

            cursor.execute(
                "SELECT COALESCE(SUM(net_reward),0) FROM public_mining_events WHERE miner_id = ? AND timestamp >= ?",
                (miner_id, day_start),
            )
            today_reward = cursor.fetchone()[0]

            cursor.execute(
                """
                SELECT timestamp, net_reward, hashrate
                FROM public_mining_events
                WHERE miner_id = ?
                ORDER BY id DESC
                LIMIT 15
                """,
                (miner_id,),
            )
            recent = [dict(row) for row in cursor.fetchall()]

            return {
                "miner_id": miner["miner_id"],
                "wallet_address": miner["wallet_address"],
                "last_seen": miner["last_seen"],
                "total_reward": float(total_reward or 0),
                "today_reward": float(today_reward or 0),
                "avg_hashrate": float(avg_hashrate or 0),
                "total_ticks": int(total_ticks or 0),
                "recent_events": recent,
            }

    def get_public_network_snapshot(self):
        five_mins_ago = int(time.time()) - 300
        day_start = int(time.time()) - 86400
        with self.lock, self.connect() as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()

            cursor.execute(
                "SELECT COUNT(*) FROM miners WHERE banned = 0 AND COALESCE(last_seen, 0) >= ?",
                (five_mins_ago,),
            )
            miners_online = cursor.fetchone()[0]

            cursor.execute(
                "SELECT COALESCE(SUM(hashrate),0), COALESCE(SUM(net_reward),0) FROM public_mining_events WHERE timestamp >= ?",
                (day_start,),
            )
            hashrate_24h, rewards_24h = cursor.fetchone()

            cursor.execute(
                "SELECT COALESCE(AVG(hashrate),0) FROM public_mining_events WHERE timestamp >= ?",
                (five_mins_ago,),
            )
            avg_recent_hash = cursor.fetchone()[0]

            return {
                "miners_online": int(miners_online or 0),
                "hashrate_24h": float(hashrate_24h or 0),
                "rewards_24h": float(rewards_24h or 0),
                "avg_recent_hashrate": float(avg_recent_hash or 0),
                "pool_fee_percent": self._get_float_config('public_pool_fee_percent', 1.0),
            }

    def get_public_leaderboard(self, limit=50):
        safe_limit = max(1, min(int(limit), 200))
        day_start = int(time.time()) - 86400
        with self.lock, self.connect() as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                    m.miner_id,
                    m.wallet_address,
                    COALESCE(SUM(e.net_reward), 0) AS total_reward,
                    COALESCE(AVG(e.hashrate), 0) AS avg_hashrate,
                    COALESCE(SUM(CASE WHEN e.timestamp >= ? THEN e.net_reward ELSE 0 END), 0) AS today_reward,
                    MAX(e.timestamp) AS last_mined_at,
                    COUNT(e.id) AS ticks
                FROM miners m
                LEFT JOIN public_mining_events e ON e.miner_id = m.miner_id
                WHERE m.banned = 0
                GROUP BY m.miner_id, m.wallet_address
                ORDER BY total_reward DESC
                LIMIT ?
                """,
                (day_start, safe_limit),
            )
            rows = [dict(r) for r in cursor.fetchall()]
            for idx, row in enumerate(rows):
                row["rank"] = idx + 1
                row["total_reward"] = float(row.get("total_reward") or 0)
                row["avg_hashrate"] = float(row.get("avg_hashrate") or 0)
                row["today_reward"] = float(row.get("today_reward") or 0)
                row["ticks"] = int(row.get("ticks") or 0)
            return rows

    def _get_miner_payout_summary(self, miner_id):
        with self.lock, self.connect() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT COALESCE(SUM(net_reward),0) FROM public_mining_events WHERE miner_id = ?",
                (miner_id,),
            )
            total_earned = float(cursor.fetchone()[0] or 0)
            cursor.execute(
                "SELECT COALESCE(SUM(amount),0) FROM payout_requests WHERE miner_id = ? AND status IN ('APPROVED','PAID')",
                (miner_id,),
            )
            total_paid = float(cursor.fetchone()[0] or 0)
            cursor.execute(
                "SELECT COALESCE(SUM(amount),0) FROM payout_requests WHERE miner_id = ? AND status = 'PENDING'",
                (miner_id,),
            )
            pending = float(cursor.fetchone()[0] or 0)
            return {
                "total_earned": total_earned,
                "total_paid": total_paid,
                "pending": pending,
                "available": max(0.0, total_earned - total_paid - pending),
            }

    def create_payout_request(self, miner_id, amount):
        safe_amount = float(amount)
        if safe_amount <= 0:
            raise ValueError("amount must be positive")

        with self.lock, self.connect() as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            cursor.execute(
                "SELECT wallet_address FROM miners WHERE miner_id = ?",
                (miner_id,),
            )
            miner = cursor.fetchone()
            if not miner:
                raise ValueError("miner not found")

        summary = self._get_miner_payout_summary(miner_id)
        if safe_amount > summary["available"]:
            raise ValueError("insufficient available balance")

        now = int(time.time())
        with self.lock, self.connect() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                INSERT INTO payout_requests
                (miner_id, wallet_address, amount, status, note, requested_at)
                VALUES (?, ?, ?, 'PENDING', ?, ?)
                """,
                (miner_id, miner["wallet_address"], safe_amount, "Requested by miner", now),
            )
            conn.commit()
            request_id = cursor.lastrowid

        return {
            "request_id": request_id,
            "miner_id": miner_id,
            "wallet_address": miner["wallet_address"],
            "amount": safe_amount,
            "status": "PENDING",
            "available_after_request": max(0.0, summary["available"] - safe_amount),
        }

    def list_payout_requests(self, status=None, limit=200, from_ts=None, to_ts=None):
        safe_limit = max(1, min(int(limit), 500))
        with self.lock, self.connect() as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            query = (
                "SELECT id, miner_id, wallet_address, amount, status, tx_hash, note, requested_at, processed_at "
                "FROM payout_requests WHERE 1=1"
            )
            params = []
            if status:
                query += " AND status = ?"
                params.append(status)
            if from_ts is not None:
                query += " AND requested_at >= ?"
                params.append(int(from_ts))
            if to_ts is not None:
                query += " AND requested_at <= ?"
                params.append(int(to_ts))
            query += " ORDER BY id DESC LIMIT ?"
            params.append(safe_limit)

            cursor.execute(query, tuple(params))
            rows = [dict(r) for r in cursor.fetchall()]
            for row in rows:
                row["amount"] = float(row.get("amount") or 0)
            return rows

    def update_payout_request_status(self, request_id, status, note=None, tx_hash=None, actor=None):
        if status not in ("APPROVED", "PAID", "REJECTED"):
            raise ValueError("invalid payout status")
        now = int(time.time())
        with self.lock, self.connect() as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            cursor.execute(
                "SELECT id, miner_id, status FROM payout_requests WHERE id = ?",
                (request_id,),
            )
            existing = cursor.fetchone()
            if not existing:
                raise ValueError("payout request not found")

            current_status = existing["status"]
            if status in ("APPROVED", "REJECTED") and current_status != "PENDING":
                raise ValueError("only pending requests can be approved or rejected")
            if status == "PAID" and current_status != "APPROVED":
                raise ValueError("only approved requests can be marked as paid")

            cursor.execute(
                """
                UPDATE payout_requests
                SET status = ?, note = COALESCE(?, note), tx_hash = COALESCE(?, tx_hash), processed_at = ?
                WHERE id = ?
                """,
                (status, note, tx_hash, now, request_id),
            )
            cursor.execute(
                """
                INSERT INTO payout_audit_logs
                (payout_request_id, miner_id, actor, from_status, to_status, tx_hash, note, changed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    request_id,
                    existing["miner_id"],
                    actor,
                    current_status,
                    status,
                    tx_hash,
                    note,
                    now,
                ),
            )
            conn.commit()

    def get_recent_payout_audit_logs(self, limit=200, from_ts=None, to_ts=None):
        safe_limit = max(1, min(int(limit), 500))
        with self.lock, self.connect() as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            query = (
                "SELECT id, payout_request_id, miner_id, actor, from_status, to_status, tx_hash, note, changed_at "
                "FROM payout_audit_logs WHERE 1=1"
            )
            params = []
            if from_ts is not None:
                query += " AND changed_at >= ?"
                params.append(int(from_ts))
            if to_ts is not None:
                query += " AND changed_at <= ?"
                params.append(int(to_ts))
            query += " ORDER BY id DESC LIMIT ?"
            params.append(safe_limit)

            cursor.execute(query, tuple(params))
            return [dict(r) for r in cursor.fetchall()]

    def get_payout_summary(self):
        with self.lock, self.connect() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                    status,
                    COUNT(*) AS item_count,
                    COALESCE(SUM(amount), 0) AS total_amount
                FROM payout_requests
                GROUP BY status
                """
            )
            by_status = {"PENDING": {"count": 0, "amount": 0.0}, "APPROVED": {"count": 0, "amount": 0.0}, "PAID": {"count": 0, "amount": 0.0}, "REJECTED": {"count": 0, "amount": 0.0}}
            for row in cursor.fetchall():
                status, count, amount = row
                if status in by_status:
                    by_status[status]["count"] = int(count or 0)
                    by_status[status]["amount"] = float(amount or 0)

            cursor.execute(
                "SELECT COALESCE(SUM(net_reward), 0) FROM public_mining_events"
            )
            total_mined = float(cursor.fetchone()[0] or 0)

            return {
                "pending_count": by_status["PENDING"]["count"],
                "pending_amount": by_status["PENDING"]["amount"],
                "approved_count": by_status["APPROVED"]["count"],
                "approved_amount": by_status["APPROVED"]["amount"],
                "paid_count": by_status["PAID"]["count"],
                "paid_amount": by_status["PAID"]["amount"],
                "rejected_count": by_status["REJECTED"]["count"],
                "rejected_amount": by_status["REJECTED"]["amount"],
                "outstanding_amount": by_status["PENDING"]["amount"] + by_status["APPROVED"]["amount"],
                "total_mined_amount": total_mined,
            }

    def issue_auth_token(self, miner_id, wallet_address):
        return secrets.token_urlsafe(32)

    def get_dashboard_stats(self):
        with self.lock, self.connect() as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) as total_miners FROM miners WHERE banned = 0")
            total_miners = cursor.fetchone()['total_miners']
            cursor.execute("SELECT SUM(reward_amount) as total_minted FROM rewards WHERE status = 'SUCCESS'")
            res_minted = cursor.fetchone()['total_minted']
            total_minted = float(res_minted) if res_minted else 0.0
            cursor.execute("SELECT SUM(pool_fee_paid) as total_fees FROM rewards WHERE status = 'SUCCESS'")
            res_fees = cursor.fetchone()['total_fees']
            total_pool_earnings = float(res_fees) if res_fees else 0.0
            cursor.execute("SELECT * FROM rewards ORDER BY id DESC LIMIT 10")
            recent_txs = [dict(row) for row in cursor.fetchall()]
            five_mins_ago = int(time.time()) - 300
            cursor.execute("SELECT miner_id, wallet_address, last_seen FROM miners WHERE last_seen > ? AND banned = 0", (five_mins_ago,))
            active_miners = [dict(row) for row in cursor.fetchall()]
            return {
                "total_miners": total_miners, "total_minted": total_minted,
                "total_pool_earnings": total_pool_earnings, "active_miners": active_miners,
                "recent_transactions": recent_txs, "difficulty": self.get_difficulty()
            }