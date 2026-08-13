import time
import json
import hashlib
import uuid
import urllib.request

SERVER_URL = "http://localhost:8080"
MINER_ID = "DfXgNqTaWKKna2iwKtj5o6QcMMjhcJhGAowbhKyfqZZY"

def send_api(endpoint, payload=None):
    try:
        url = f"{SERVER_URL}{endpoint}"
        req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read().decode())
    except:
        return None

def start():
    print(f"🚀 Initializing Miner Engine [{MINER_ID}]")
    prefix = "00"  # ความยากเริ่มต้น 4 ตัว
    nonce = 0
    while True:
        raw_data = f"{MINER_ID}OBZ_GENESIS{nonce}"
        h = hashlib.sha256(raw_data.encode()).hexdigest()
        if h.startswith(prefix):
            print(f"\n[💎] Block Solved! Nonce: {nonce}")
            res = send_api("/submit_share", {"miner_id": MINER_ID, "nonce": str(nonce)})
            if res and res.get("status") == "ACCEPTED":
                print(f"    ▶️ Miner Net Reward: +{res.get('net_miner_reward')} OBZ (Pool Fee Deducted)")
            nonce += 1
        nonce += 1

if __name__ == "__main__":
    start()
