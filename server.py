import hashlib
import time
import secrets
import os
from fastapi import FastAPI, Request, HTTPException, Query
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn
from database import OBZDatabase

BLOCK_REWARD = 10.0           
POOL_FEE_PERCENT = 2.0        
POOL_OWNER_WALLET = "DfXgNqTaWKKna2iwKtj5o6QcMMjhcJhGAowbhKyfqZZY" 

app = FastAPI(title="OBZ Commercial Mining Engine")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://obzexchange.com",
        "http://obzexchange.com",
        "https://www.obzexchange.com",
        "http://www.obzexchange.com",
        "http://localhost:8765",
        "http://127.0.0.1:8765",
        "http://localhost:5500",
        "http://127.0.0.1:5500",
    ],
    allow_origin_regex=r"https://(?:[a-z0-9-]+\.)?netlify\.app",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

db = OBZDatabase()

MINING_TICK_COOLDOWN_SECONDS = 8
ANTI_BOT_CHALLENGE_TTL_SECONDS = 120
ANTI_BOT_POW_DIFFICULTY = 4
AUTH_SESSION_TTL_SECONDS = 86400
# No hardcoded fallback: a static secret here would be exposed in the public repo.
ADMIN_API_KEY = os.getenv("OBZ_ADMIN_API_KEY")
if not ADMIN_API_KEY:
    ADMIN_API_KEY = secrets.token_urlsafe(32)
    print(
        "[WARN] OBZ_ADMIN_API_KEY not set in .env — generated a temporary key for this "
        f"process only: {ADMIN_API_KEY} (set OBZ_ADMIN_API_KEY in .env for a stable key)"
    )
ADMIN_SESSION_TTL_SECONDS = 900
_last_tick_by_miner = {}
_active_challenges = {}
_auth_sessions = {}
_rate_limit_buckets = {}
_admin_sessions = {}

class SubmitPayload(BaseModel):
    miner_id: str
    nonce: str
    last_block_hash: str = "OBZ_GENESIS"


class PublicRegisterPayload(BaseModel):
    miner_id: str
    wallet_address: str


class PublicChallengePayload(BaseModel):
    wallet_address: str


class PublicAuthorizePayload(BaseModel):
    miner_id: str
    wallet_address: str
    challenge_id: str
    challenge_nonce: str


class PublicMinePayload(BaseModel):
    miner_id: str
    wallet_address: str
    hashrate: float
    session_token: str


class PayoutRequestPayload(BaseModel):
    miner_id: str
    amount: float
    session_token: str


class PayoutActionPayload(BaseModel):
    admin_session: str
    tx_hash: str = ""
    note: str = ""


class AdminSessionPayload(BaseModel):
    admin_key: str


def _client_ip(request: Request):
    xff = request.headers.get("x-forwarded-for", "").strip()
    if xff:
        return xff.split(",")[0].strip()
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


def _enforce_rate_limit(bucket_key: str, limit: int, window_seconds: int):
    now = time.time()
    events = _rate_limit_buckets.get(bucket_key, [])
    events = [t for t in events if now - t <= window_seconds]
    if len(events) >= limit:
        raise HTTPException(status_code=429, detail="rate limit exceeded")
    events.append(now)
    _rate_limit_buckets[bucket_key] = events


def _validate_auth(miner_id: str, wallet_address: str, session_token: str, request: Request):
    session = _auth_sessions.get(session_token)
    if not session:
        raise HTTPException(status_code=401, detail="invalid session token")
    if time.time() > session["expires_at"]:
        _auth_sessions.pop(session_token, None)
        raise HTTPException(status_code=401, detail="session expired")
    if session["miner_id"] != miner_id or session["wallet_address"].lower() != wallet_address.lower():
        raise HTTPException(status_code=401, detail="session does not match miner/wallet")

    session["last_seen"] = time.time()
    _auth_sessions[session_token] = session


def _validate_admin_session(admin_session: str, request: Request):
    sess = _admin_sessions.get(admin_session)
    if not sess:
        raise HTTPException(status_code=401, detail="invalid admin session")
    if time.time() > sess["expires_at"]:
        _admin_sessions.pop(admin_session, None)
        raise HTTPException(status_code=401, detail="admin session expired")

    ip = _client_ip(request)
    if sess["ip"] != ip:
        raise HTTPException(status_code=401, detail="admin session ip mismatch")

    sess["last_seen"] = time.time()
    _admin_sessions[admin_session] = sess
    return sess


def _admin_actor_label(sess):
    return f"admin@{sess.get('ip', 'unknown')}"

@app.post("/submit_share")
async def submit_share(payload: SubmitPayload, request: Request):
    current_diff = db.get_difficulty()
    target_prefix = "0" * current_diff
    raw_data = f"{payload.miner_id}{payload.last_block_hash}{payload.nonce}".encode()
    calculated_hash = hashlib.sha256(raw_data).hexdigest()
    
    if not calculated_hash.startswith(target_prefix):
        raise HTTPException(status_code=400, detail="Invalid proof.")

    pool_fee = (POOL_FEE_PERCENT / 100.0) * BLOCK_REWARD 
    net_miner_reward = BLOCK_REWARD - pool_fee           

    reward_id = db.record_share_with_fee(
        miner_id=payload.miner_id, nonce=payload.nonce,
        difficulty=current_diff, net_reward=net_miner_reward, pool_fee=pool_fee
    )
    return {"status": "ACCEPTED", "gross_reward": BLOCK_REWARD, "pool_fee_deducted": pool_fee, "net_miner_reward": net_miner_reward, "tx_id": reward_id}


@app.post("/api/mining/register")
async def register_public_miner(payload: PublicRegisterPayload):
    miner_id = payload.miner_id.strip()
    wallet = payload.wallet_address.strip()
    if not miner_id or not wallet:
        raise HTTPException(status_code=400, detail="miner_id and wallet_address are required")
    db.upsert_public_miner(miner_id=miner_id, wallet_address=wallet)
    return {"status": "REGISTERED", "miner_id": miner_id, "wallet_address": wallet}


@app.post("/api/mining/challenge")
async def create_public_mining_challenge(payload: PublicChallengePayload, request: Request):
    wallet = payload.wallet_address.strip().lower()
    if not wallet:
        raise HTTPException(status_code=400, detail="wallet_address is required")

    ip = _client_ip(request)
    _enforce_rate_limit(f"challenge:{ip}", limit=20, window_seconds=300)
    _enforce_rate_limit(f"challenge-wallet:{wallet}", limit=12, window_seconds=300)

    challenge_id = secrets.token_urlsafe(16)
    challenge = secrets.token_hex(16)
    now = time.time()
    _active_challenges[challenge_id] = {
        "wallet": wallet,
        "challenge": challenge,
        "ip": ip,
        "expires_at": now + ANTI_BOT_CHALLENGE_TTL_SECONDS,
        "used": False,
    }

    return {
        "challenge_id": challenge_id,
        "challenge": challenge,
        "difficulty": ANTI_BOT_POW_DIFFICULTY,
        "algorithm": "sha256(challenge:nonce) startsWith zeros",
        "expires_in": ANTI_BOT_CHALLENGE_TTL_SECONDS,
    }


@app.post("/api/mining/authorize")
async def authorize_public_miner(payload: PublicAuthorizePayload, request: Request):
    miner_id = payload.miner_id.strip()
    wallet = payload.wallet_address.strip().lower()
    if not miner_id or not wallet:
        raise HTTPException(status_code=400, detail="miner_id and wallet_address are required")

    ip = _client_ip(request)
    _enforce_rate_limit(f"auth:{ip}", limit=20, window_seconds=300)
    _enforce_rate_limit(f"auth-wallet:{wallet}", limit=10, window_seconds=300)

    challenge_state = _active_challenges.get(payload.challenge_id)
    if not challenge_state:
        raise HTTPException(status_code=400, detail="challenge not found")
    if challenge_state["used"]:
        raise HTTPException(status_code=400, detail="challenge already used")
    if time.time() > challenge_state["expires_at"]:
        raise HTTPException(status_code=400, detail="challenge expired")
    if challenge_state["wallet"] != wallet:
        raise HTTPException(status_code=400, detail="challenge wallet mismatch")
    nonce = payload.challenge_nonce.strip()
    pow_hash = hashlib.sha256(f"{challenge_state['challenge']}:{nonce}".encode()).hexdigest()
    if not pow_hash.startswith("0" * ANTI_BOT_POW_DIFFICULTY):
        raise HTTPException(status_code=400, detail="invalid challenge solution")

    challenge_state["used"] = True
    _active_challenges[payload.challenge_id] = challenge_state

    db.upsert_public_miner(miner_id=miner_id, wallet_address=wallet)
    token = secrets.token_urlsafe(32)
    _auth_sessions[token] = {
        "miner_id": miner_id,
        "wallet_address": wallet,
        "ip": ip,
        "created_at": time.time(),
        "last_seen": time.time(),
        "expires_at": time.time() + AUTH_SESSION_TTL_SECONDS,
    }

    return {
        "status": "AUTHORIZED",
        "miner_id": miner_id,
        "wallet_address": wallet,
        "session_token": token,
        "expires_in": AUTH_SESSION_TTL_SECONDS,
    }


@app.post("/api/mining/mine")
async def mine_public_tick(payload: PublicMinePayload, request: Request):
    miner_id = payload.miner_id.strip()
    wallet = payload.wallet_address.strip()
    if not miner_id or not wallet:
        raise HTTPException(status_code=400, detail="miner_id and wallet_address are required")

    _validate_auth(miner_id=miner_id, wallet_address=wallet, session_token=payload.session_token, request=request)
    _enforce_rate_limit(f"mine:{miner_id}", limit=8, window_seconds=60)

    now = time.time()
    last_tick = _last_tick_by_miner.get(miner_id)
    if last_tick and now - last_tick < MINING_TICK_COOLDOWN_SECONDS:
        wait_for = MINING_TICK_COOLDOWN_SECONDS - (now - last_tick)
        raise HTTPException(status_code=429, detail=f"tick cooldown active ({wait_for:.1f}s)")

    db.upsert_public_miner(miner_id=miner_id, wallet_address=wallet)
    reward = db.record_public_mining_tick(miner_id=miner_id, wallet_address=wallet, hashrate=payload.hashrate)
    _last_tick_by_miner[miner_id] = now
    return {"status": "MINED", **reward}


@app.get("/api/mining/stats/{miner_id}")
async def get_public_miner_stats(miner_id: str):
    snapshot = db.get_public_miner_snapshot(miner_id.strip())
    if not snapshot:
        raise HTTPException(status_code=404, detail="miner not found")
    return snapshot


@app.get("/api/mining/network")
async def get_public_network_stats():
    return db.get_public_network_snapshot()


@app.get("/api/mining/leaderboard")
async def get_public_leaderboard(limit: int = Query(default=50, ge=1, le=200)):
    return {"leaders": db.get_public_leaderboard(limit=limit)}


@app.post("/api/admin/session")
async def create_admin_session(payload: AdminSessionPayload, request: Request):
    if payload.admin_key != ADMIN_API_KEY:
        raise HTTPException(status_code=401, detail="invalid admin key")

    ip = _client_ip(request)
    _enforce_rate_limit(f"admin-session:{ip}", limit=12, window_seconds=300)

    token = secrets.token_urlsafe(32)
    _admin_sessions[token] = {
        "ip": ip,
        "created_at": time.time(),
        "last_seen": time.time(),
        "expires_at": time.time() + ADMIN_SESSION_TTL_SECONDS,
        "actor": f"admin@{ip}",
    }
    return {
        "status": "AUTHORIZED",
        "admin_session": token,
        "expires_in": ADMIN_SESSION_TTL_SECONDS,
    }


@app.post("/api/admin/session/refresh")
async def refresh_admin_session(admin_session: str, request: Request):
    sess = _validate_admin_session(admin_session=admin_session, request=request)
    sess["expires_at"] = time.time() + ADMIN_SESSION_TTL_SECONDS
    sess["last_seen"] = time.time()
    _admin_sessions[admin_session] = sess
    return {
        "status": "REFRESHED",
        "admin_session": admin_session,
        "expires_in": ADMIN_SESSION_TTL_SECONDS,
    }


@app.post("/api/admin/session/logout")
async def logout_admin_session(admin_session: str, request: Request):
    _validate_admin_session(admin_session=admin_session, request=request)
    _admin_sessions.pop(admin_session, None)
    return {"status": "LOGGED_OUT"}


@app.post("/api/mining/payout/request")
async def create_payout_request(payload: PayoutRequestPayload, request: Request):
    miner_id = payload.miner_id.strip()
    if not miner_id:
        raise HTTPException(status_code=400, detail="miner_id is required")
    snapshot = db.get_public_miner_snapshot(miner_id)
    if not snapshot:
        raise HTTPException(status_code=404, detail="miner not found")

    _validate_auth(
        miner_id=miner_id,
        wallet_address=snapshot["wallet_address"],
        session_token=payload.session_token,
        request=request,
    )
    _enforce_rate_limit(f"payout-request:{miner_id}", limit=5, window_seconds=3600)

    try:
        result = db.create_payout_request(miner_id=miner_id, amount=payload.amount)
    except ValueError as err:
        raise HTTPException(status_code=400, detail=str(err)) from err
    return {"status": "QUEUED", **result}


@app.get("/api/mining/payout/queue")
async def list_payout_queue(
    admin_session: str,
    request: Request,
    status: str = Query(default="", pattern="^(|PENDING|APPROVED|PAID|REJECTED)$"),
    limit: int = Query(default=100, ge=1, le=500),
    from_ts: int | None = Query(default=None, ge=0),
    to_ts: int | None = Query(default=None, ge=0),
):
    _validate_admin_session(admin_session=admin_session, request=request)
    rows = db.list_payout_requests(status=status or None, limit=limit, from_ts=from_ts, to_ts=to_ts)
    return {"items": rows}


@app.get("/api/mining/payout/summary")
async def get_payout_summary(admin_session: str, request: Request):
    _validate_admin_session(admin_session=admin_session, request=request)
    return db.get_payout_summary()


@app.get("/api/mining/payout/audit")
async def get_payout_audit_logs(
    admin_session: str,
    request: Request,
    limit: int = Query(default=120, ge=1, le=500),
    from_ts: int | None = Query(default=None, ge=0),
    to_ts: int | None = Query(default=None, ge=0),
):
    _validate_admin_session(admin_session=admin_session, request=request)
    return {"items": db.get_recent_payout_audit_logs(limit=limit, from_ts=from_ts, to_ts=to_ts)}


@app.post("/api/mining/payout/{request_id}/approve")
async def approve_payout_request(request_id: int, payload: PayoutActionPayload, request: Request):
    sess = _validate_admin_session(admin_session=payload.admin_session, request=request)
    try:
        db.update_payout_request_status(
            request_id=request_id,
            status="APPROVED",
            note=payload.note or "Approved by admin",
            tx_hash=payload.tx_hash or None,
            actor=_admin_actor_label(sess),
        )
    except ValueError as err:
        raise HTTPException(status_code=400, detail=str(err)) from err
    return {"status": "APPROVED", "request_id": request_id}


@app.post("/api/mining/payout/{request_id}/reject")
async def reject_payout_request(request_id: int, payload: PayoutActionPayload, request: Request):
    sess = _validate_admin_session(admin_session=payload.admin_session, request=request)
    try:
        db.update_payout_request_status(
            request_id=request_id,
            status="REJECTED",
            note=payload.note or "Rejected by admin",
            tx_hash=payload.tx_hash or None,
            actor=_admin_actor_label(sess),
        )
    except ValueError as err:
        raise HTTPException(status_code=400, detail=str(err)) from err
    return {"status": "REJECTED", "request_id": request_id}


@app.post("/api/mining/payout/{request_id}/mark-paid")
async def mark_payout_as_paid(request_id: int, payload: PayoutActionPayload, request: Request):
    sess = _validate_admin_session(admin_session=payload.admin_session, request=request)
    try:
        db.update_payout_request_status(
            request_id=request_id,
            status="PAID",
            note=payload.note or "Marked as paid by admin",
            tx_hash=payload.tx_hash or None,
            actor=_admin_actor_label(sess),
        )
    except ValueError as err:
        raise HTTPException(status_code=400, detail=str(err)) from err
    return {"status": "PAID", "request_id": request_id}

@app.get("/", response_class=HTMLResponse)
async def web_dashboard():
    stats = db.get_dashboard_stats()
    active_count = len(stats["active_miners"])
    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>OBZ Commercial Dashboard</title>
        <meta charset="utf-8">
        <style>
            body {{ font-family: system-ui; background: #0b0f19; color: #f8fafc; padding: 20px; }}
            .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 20px; margin-bottom: 20px; }}
            .card {{ background: #111827; padding: 20px; border-radius: 8px; border: 1px solid #1f2937; }}
            h1 {{ color: #38bdf8; }}
            table {{ width: 100%; border-collapse: collapse; background: #111827; }}
            th, td {{ padding: 12px; text-align: left; border-bottom: 1px solid #1f2937; }}
            th {{ background: #1f2937; color: #38bdf8; }}
        </style>
        <meta http-equiv="refresh" content="3">
    </head>
    <body>
        <h1>💸 OBZ Mining Pool Portal (Commercial Edition)</h1>
        <div class="grid">
            <div class="card"><h3>Active Miners</h3><p>{active_count} Online</p></div>
            <div class="card"><h3>Total Miners Payout</h3><p style="color:#eab308;">{stats["total_minted"]:.2f} OBZ</p></div>
            <div class="card"><h3>Pool Revenue</h3><p style="color:#22c55e;">+{stats["total_pool_earnings"]:.2f} OBZ</p></div>
            <div class="card"><h3>Pool Fee Rate</h3><p style="color:#a855f7;">{POOL_FEE_PERCENT}%</p></div>
        </div>
        <h2>📋 Audit Ledger</h2>
        <table>
            <tr><th>Tx ID</th><th>Miner Node ID</th><th>Net Paid to Miner</th><th>Fee Taken by Pool</th></tr>
            {"".join(f"<tr><td>#{tx['id']}</td><td>{tx['miner_id']}</td><td>{tx['reward_amount']:.2f} OBZ</td><td style='color:#22c55e;'>+{tx['pool_fee_paid']:.2f} OBZ</td></tr>" for tx in stats["recent_transactions"])}
        </table>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8080)