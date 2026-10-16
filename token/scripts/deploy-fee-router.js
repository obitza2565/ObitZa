const { ethers } = require("hardhat");

// BSC MAINNET addresses (defaults). Override via env if needed.
const PANCAKE_ROUTER = process.env.PANCAKE_ROUTER || "0x10ED43C718714eb63d5aA57B78B54704E256024E"; // PancakeSwap Router V2 mainnet
const USDT          = process.env.USDT_ADDRESS    || "0x55d398326f99059fF775485246999027B3197955"; // USDT mainnet (18 decimals)
const OBZ           = process.env.OBZ_TOKEN_ADDRESS || "0x5e1834c8D1B50F0B9e13712CD9ed1d90892a9Bf7"; // OBZ mainnet
const WBNB          = process.env.WBNB_ADDRESS    || "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"; // WBNB mainnet
const FEE_WALLET    = process.env.FEE_WALLET      || "0x41a0096ef2E784d574156Ddec32853B666C6dbE1"; // admin/hot wallet

async function main() {
  // Guard: without PRIVATE_KEY in token/.env, Hardhat has no signer and
  // deployer would be undefined (the "reading 'address'" crash).
  const signers = await ethers.getSigners();
  if (!process.env.PRIVATE_KEY || signers.length === 0) {
    console.error("❌ ไม่พบ PRIVATE_KEY — ไม่มีบัญชี deployer ให้ใช้งาน");
    console.error("");
    console.error("วิธีแก้:");
    console.error("  1. สร้างไฟล์ token/.env (อยู่ใน .gitignore แล้ว ปลอดภัย)");
    console.error("  2. ใส่บรรทัดนี้:  PRIVATE_KEY=0x<private key 64 ตัวอักษรของกระเป๋า deployer>");
    console.error("  3. กระเป๋านั้นต้องมี BNB mainnet สำหรับค่าแก๊ส (~0.01 BNB)");
    console.error("  4. รันใหม่: npx hardhat run scripts/deploy-fee-router.js --network bscMainnet");
    process.exit(1);
  }
  const [deployer] = signers;
  const net = await ethers.provider.getNetwork();

  console.log("═══════════════════════════════════════");
  console.log("  OBZ Fee Router Deployment");
  console.log("═══════════════════════════════════════");
  console.log("Deployer   :", deployer.address);
  console.log("Balance    :", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "BNB");
  console.log("Chain ID   :", net.chainId.toString());
  console.log("Router     :", PANCAKE_ROUTER);
  console.log("USDT       :", USDT);
  console.log("OBZ        :", OBZ);
  console.log("WBNB       :", WBNB);
  console.log("Fee Wallet :", FEE_WALLET);
  console.log("Fee        : 1% | Daily limit: 10 USDT per wallet");

  const OBZFeeRouter = await ethers.getContractFactory("OBZFeeRouter");
  const router = await OBZFeeRouter.deploy(PANCAKE_ROUTER, USDT, OBZ, WBNB, FEE_WALLET);
  await router.waitForDeployment();

  const addr = await router.getAddress();
  console.log("\n✅ OBZFeeRouter deployed at:", addr);
  console.log("Fee wallet  :", await router.feeWallet());
  console.log("Daily limit :", ethers.formatEther(await router.dailyLimitUsdt()), "USDT");

  console.log("\n── NEXT STEPS ──");
  console.log("1. Paste this into exchange/app-config.js:");
  console.log(`   feeRouter: '${addr}',`);
  console.log("2. Create PancakeSwap liquidity pools (scripts/add-liquidity.js):");
  console.log("   - OBZ/USDT  (1 OBZ = 1 USDT initial price)");
  console.log("   - OBZ/BNB   (rate follows the USDT pool)");
  console.log("3. Verify contract on BscScan (optional but recommended):");
  console.log(`   npx hardhat verify --network bscMainnet ${addr} ${PANCAKE_ROUTER} ${USDT} ${OBZ} ${WBNB} ${FEE_WALLET}`);
  console.log("═══════════════════════════════════════");
}

main().catch((e) => { console.error(e); process.exit(1); });
