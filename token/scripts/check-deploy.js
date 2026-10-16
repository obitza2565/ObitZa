const { ethers } = require("hardhat");

// Reconstructs the contract address from the last deployment attempt and
// verifies whether bytecode actually exists there on-chain.
async function main() {
  const deployer = "0x41a0096ef2E784d574156Ddec32853B666C6dbE1";
  const nonce = await ethers.provider.getTransactionCount(deployer);
  console.log("Deployer nonce now:", nonce);

  for (let n = Math.max(0, nonce - 3); n < nonce; n++) {
    const predicted = ethers.getCreateAddress({ from: deployer, nonce: n });
    const code = await ethers.provider.getCode(predicted);
    const exists = code && code !== "0x";
    console.log(`nonce ${n} -> ${predicted}  code: ${exists ? code.length / 2 - 1 + " bytes ✅" : "none"}`);
    if (exists) {
      console.log("\nDEPLOYED_CONTRACT=" + predicted);
    }
  }
}

main().catch((e) => { console.error(e.message); process.exit(1); });
