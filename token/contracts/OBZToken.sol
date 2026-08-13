// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title OBZ Token
 * @notice ERC-20 token for OBZ Exchange — mining rewards, staking, and fee discounts.
 */
contract OBZToken is ERC20, ERC20Burnable, Ownable {
    uint256 public constant MAX_SUPPLY     = 1_000_000_000 * 10 ** 18; // 1B OBZ
    uint256 public constant MINING_REWARD  = 10 * 10 ** 18;            // 10 OBZ per block
    uint256 public constant STAKE_MIN      = 500 * 10 ** 18;           // 500 OBZ for Pro tier

    uint256 public totalMined;
    uint256 public lastMineBlock;

    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public stakeTimestamp;
    mapping(address => bool)    public isMiner;

    event Mined(address indexed miner, uint256 amount, uint256 blockNumber);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, uint256 reward);

    constructor(address initialOwner) ERC20("OBZ Token", "OBZ") Ownable(initialOwner) {
        // Mint initial supply to deployer: 100M for exchange liquidity
        _mint(initialOwner, 100_000_000 * 10 ** 18);
    }

    // ── MINING ──────────────────────────────────────────────────────────────

    /// Register an address as a miner (only owner / exchange contract)
    function addMiner(address miner) external onlyOwner {
        isMiner[miner] = true;
    }

    /// Claim mining reward — one reward per block per miner
    function claimMiningReward() external {
        require(isMiner[msg.sender], "Not a registered miner");
        require(block.number > lastMineBlock, "Already mined this block");
        require(totalSupply() + MINING_REWARD <= MAX_SUPPLY, "Max supply reached");

        lastMineBlock = block.number;
        totalMined += MINING_REWARD;
        _mint(msg.sender, MINING_REWARD);
        emit Mined(msg.sender, MINING_REWARD, block.number);
    }

    /// Owner can mint mining rewards to any miner address directly
    function mintMiningReward(address miner, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        totalMined += amount;
        _mint(miner, amount);
        emit Mined(miner, amount, block.number);
    }

    // ── STAKING ─────────────────────────────────────────────────────────────

    /// Stake OBZ to unlock Pro tier fee discounts
    function stake(uint256 amount) external {
        require(amount >= STAKE_MIN, "Minimum 500 OBZ to stake");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _transfer(msg.sender, address(this), amount);
        stakedBalance[msg.sender] += amount;
        stakeTimestamp[msg.sender] = block.timestamp;
        emit Staked(msg.sender, amount);
    }

    /// Unstake and collect APY reward (~18% annual, pro-rated by seconds)
    function unstake() external {
        uint256 staked = stakedBalance[msg.sender];
        require(staked > 0, "Nothing staked");

        uint256 duration = block.timestamp - stakeTimestamp[msg.sender];
        // 18% APY = 18/100 / 365 days / 86400 seconds
        uint256 reward = (staked * 18 * duration) / (100 * 365 * 86400);

        stakedBalance[msg.sender] = 0;
        stakeTimestamp[msg.sender] = 0;

        // Transfer back principal
        _transfer(address(this), msg.sender, staked);

        // Mint staking reward if supply allows
        if (totalSupply() + reward <= MAX_SUPPLY) {
            _mint(msg.sender, reward);
        }

        emit Unstaked(msg.sender, staked, reward);
    }

    // ── VIEW ────────────────────────────────────────────────────────────────

    /// Returns true if address holds >= 500 OBZ (Pro tier)
    function isPro(address user) external view returns (bool) {
        return balanceOf(user) + stakedBalance[user] >= STAKE_MIN;
    }

    /// Remaining mintable supply
    function remainingSupply() external view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
    }
}
