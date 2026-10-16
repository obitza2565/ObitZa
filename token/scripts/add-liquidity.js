const { ethers } = require("hardhat");

/**
 * Adds initial liquidity to PancakeSwap for OBZ/USDT and/or OBZ/BNB.
 * Run by the token owner after deploying OBZFeeRouter.
 *
 * Required env (token/.env):
 *   PRIVATE_KEY=<owner key holding OBZ + USDT + BNB>
 * Optional env:
 *   OBZ_USDT_AMOUNT=10000   # OBZ to pair with USDT (default 10,000)
 *   USDT_AMOUNT=10000       # USDT side (1 OBZ = 1 USDT initial price)
 *   OBZ_BNB_AMOUNT=5000     # OBZ to pair with BNB
 *   BNB_AMOUNT=5            # BNB side
 *
 * Usage: npx hardhat run scripts/add-liquidity.js --network bscMainnet
 */

const PANCAKE_ROUTER = process.env.PANCAKE_ROUTER || "0x10ED43C718714eb63d5aA57B78B54704E256024E";
const USDT = process.env.USDT_ADDRESS || "0x55d398326f99059fF775485246999027B3197955";
const OBZ  = process.env.OBZ_TOKEN_ADDRESS || "0x5e1834c8D1B50F0B9e13712CD9ed1d90892a9Bf7";

const ROUTER_ABI = [
  "function addLiquidity(address tokenA, address tokenB, uint amountADesired, uint amountBDesired, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB, uint liquidity)",
  "function addLiquidityETH(address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external payable returns (uint amountToken, uint amountETH, uint liquidity)",
];
const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address owner) view returns (uint256)",
];

async function ensureAllowance(token, owner, spender, amount, label) {
  const current = await token.allowance(owner.address, spender);
  if (current < amount) {
    console.log(`Approving ${label}...`);
    const tx = await token.approve(spender, ethers.MaxUint256);
    await tx.wait();
  }
}

async function main() {
  const signers = await ethers.getSigners();
  if (!process.env.PRIVATE_KEY || signers.length === 0) {
    console.error("❌ ไม่พบ PRIVATE_KEY — สร้าง token/.env ใส่ PRIVATE_KEY=0x... ของกระเป๋าที่ถือ OBZ/USDT/BNB ก่อน");
    process.exit(1);
  }
  const [owner] = signers;
  const router = new ethers.Contract(PANCAKE_ROUTER, ROUTER_ABI, owner);
  const obz = new ethers.Contract(OBZ, ERC20_ABI, owner);
  const usdt = new ethers.Contract(USDT, ERC20_ABI, owner);

  const obzUsdtAmt = ethers.parseEther(process.env.OBZ_USDT_AMOUNT || "10000");
  const usdtAmt    = ethers.parseEther(process.env.USDT_AMOUNT || "10000");
  const obzBnbAmt  = ethers.parseEther(process.env.OBZ_BNB_AMOUNT || "5000");
  const bnbAmt     = ethers.parseEther(process.env.BNB_AMOUNT || "5");
  const deadline   = Math.floor(Date.now() / 1000) + 1800;

  console.log("Owner:", owner.address);
  console.log("OBZ balance :", ethers.formatEther(await obz.balanceOf(owner.address)));
  console.log("USDT balance:", ethers.formatEther(await usdt.balanceOf(owner.address)));
  console.log("BNB balance :", ethers.formatEther(await ethers.provider.getBalance(owner.address)));

  if (usdtAmt > 0n && obzUsdtAmt > 0n) {
    await ensureAllowance(obz, owner, PANCAKE_ROUTER, obzUsdtAmt, "OBZ");
    await ensureAllowance(usdt, owner, PANCAKE_ROUTER, usdtAmt, "USDT");
    console.log(`\nAdding OBZ/USDT liquidity: ${ethers.formatEther(obzUsdtAmt)} OBZ + ${ethers.formatEther(usdtAmt)} USDT`);
    const tx1 = await router.addLiquidity(OBZ, USDT, obzUsdtAmt, usdtAmt, 0, 0, owner.address, deadline);
    const r1 = await tx1.wait();
    console.log("OBZ/USDT pool tx:", r1.hash);
  }

  if (bnbAmt > 0n && obzBnbAmt > 0n) {
    await ensureAllowance(obz, owner, PANCAKE_ROUTER, obzBnbAmt, "OBZ");
    console.log(`\nAdding OBZ/BNB liquidity: ${ethers.formatEther(obzBnbAmt)} OBZ + ${ethers.formatEther(bnbAmt)} BNB`);
    const tx2 = await router.addLiquidityETH(OBZ, obzBnbAmt, 0, 0, owner.address, deadline, { value: bnbAmt });
    const r2 = await tx2.wait();
    console.log("OBZ/BNB pool tx:", r2.hash);
  }

  console.log("\n✅ Liquidity setup complete");
}

main().catch((e) => { console.error(e); process.exit(1); });
