const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("═══════════════════════════════════════");
  console.log("  OBZ Token Deployment");
  console.log("═══════════════════════════════════════");
  console.log("Deployer :", deployer.address);
  console.log("Balance  :", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");
  console.log("Network  :", (await ethers.provider.getNetwork()).name);

  // Deploy
  const OBZToken = await ethers.getContractFactory("OBZToken");
  const token = await OBZToken.deploy(deployer.address);
  await token.waitForDeployment();

  const addr = await token.getAddress();
  console.log("\n✅ OBZ Token deployed!");
  console.log("Contract Address :", addr);
  console.log("Token Name       :", await token.name());
  console.log("Token Symbol     :", await token.symbol());
  console.log("Decimals         :", await token.decimals());
  console.log("Total Supply     :", ethers.formatEther(await token.totalSupply()), "OBZ");
  console.log("Max Supply       :", ethers.formatEther(await token.MAX_SUPPLY()), "OBZ");
  console.log("Mining Reward    :", ethers.formatEther(await token.MINING_REWARD()), "OBZ/block");
  console.log("Deployer Balance :", ethers.formatEther(await token.balanceOf(deployer.address)), "OBZ");

  // Register deployer as miner and test a claim
  console.log("\n── Testing Mining Reward ──");
  await token.addMiner(deployer.address);
  await token.claimMiningReward();
  console.log("After mine:", ethers.formatEther(await token.balanceOf(deployer.address)), "OBZ");

  // Test staking
  console.log("\n── Testing Staking (500 OBZ) ──");
  const stakeAmt = ethers.parseEther("500");
  await token.stake(stakeAmt);
  console.log("Staked balance   :", ethers.formatEther(await token.stakedBalance(deployer.address)), "OBZ");
  console.log("Is Pro tier      :", await token.isPro(deployer.address));

  console.log("\n═══════════════════════════════════════");
  console.log("  Add to MetaMask / Exchange:");
  console.log("  Address  :", addr);
  console.log("  Symbol   : OBZ");
  console.log("  Decimals : 18");
  console.log("═══════════════════════════════════════");
}

main().catch((e) => { console.error(e); process.exit(1); });


