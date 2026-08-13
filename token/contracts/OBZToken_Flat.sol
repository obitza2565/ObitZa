// SPDX-License-Identifier: MIT
// OBZ Token — Flat file (no external imports) — paste directly into Remix IDE
pragma solidity ^0.8.20;

// ── ERC-20 Base ──────────────────────────────────────────────────────────────

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

abstract contract ERC20 is IERC20 {
    string private _name;
    string private _symbol;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    constructor(string memory name_, string memory symbol_) { _name = name_; _symbol = symbol_; }

    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function decimals() public pure returns (uint8) { return 18; }
    function totalSupply() public view returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view returns (uint256) { return _balances[account]; }

    function transfer(address to, uint256 value) public returns (bool) {
        _transfer(msg.sender, to, value); return true;
    }
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }
    function approve(address spender, uint256 value) public returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value); return true;
    }
    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        require(_allowances[from][msg.sender] >= value, "ERC20: insufficient allowance");
        _allowances[from][msg.sender] -= value;
        _transfer(from, to, value); return true;
    }
    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0) && to != address(0), "ERC20: zero address");
        require(_balances[from] >= value, "ERC20: insufficient balance");
        _balances[from] -= value;
        _balances[to] += value;
        emit Transfer(from, to, value);
    }
    function _mint(address account, uint256 value) internal {
        require(account != address(0), "ERC20: mint to zero address");
        _totalSupply += value;
        _balances[account] += value;
        emit Transfer(address(0), account, value);
    }
    function _burn(address account, uint256 value) internal {
        require(_balances[account] >= value, "ERC20: burn exceeds balance");
        _balances[account] -= value;
        _totalSupply -= value;
        emit Transfer(account, address(0), value);
    }
}

// ── OBZ Token ────────────────────────────────────────────────────────────────

contract OBZToken is ERC20 {
    address public owner;

    uint256 public constant MAX_SUPPLY    = 1_000_000_000 ether; // 1 Billion OBZ
    uint256 public constant MINING_REWARD = 10 ether;             // 10 OBZ per claim
    uint256 public constant STAKE_MIN     = 500 ether;            // 500 OBZ for Pro tier

    uint256 public totalMined;

    mapping(address => bool)    public isMiner;
    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public stakeTimestamp;
    mapping(address => uint256) public lastMinedBlock;

    event Mined(address indexed miner, uint256 amount);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 principal, uint256 reward);

    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }

    constructor() ERC20("OBZ Token", "OBZ") {
        owner = msg.sender;
        // Mint 100 million OBZ to deployer (exchange liquidity + team)
        _mint(msg.sender, 100_000_000 ether);
    }

    // ── Mining ───────────────────────────────────────────────────────────────

    function addMiner(address miner) external onlyOwner {
        isMiner[miner] = true;
    }

    function removeMiner(address miner) external onlyOwner {
        isMiner[miner] = false;
    }

    /// Claim 10 OBZ mining reward (one per block per miner)
    function claimMiningReward() external {
        require(isMiner[msg.sender], "Not a registered miner");
        require(block.number > lastMinedBlock[msg.sender], "Already mined this block");
        require(totalSupply() + MINING_REWARD <= MAX_SUPPLY, "Max supply reached");

        lastMinedBlock[msg.sender] = block.number;
        totalMined += MINING_REWARD;
        _mint(msg.sender, MINING_REWARD);
        emit Mined(msg.sender, MINING_REWARD);
    }

    /// Owner mints reward directly to a miner (for off-chain rig tracking)
    function mintMiningReward(address miner, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        totalMined += amount;
        _mint(miner, amount);
        emit Mined(miner, amount);
    }

    // ── Staking ──────────────────────────────────────────────────────────────

    /// Stake >= 500 OBZ to unlock Pro tier (60% fee discount on OBZ Exchange)
    function stake(uint256 amount) external {
        require(amount >= STAKE_MIN, "Minimum 500 OBZ");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _transfer(msg.sender, address(this), amount);
        stakedBalance[msg.sender] += amount;
        stakeTimestamp[msg.sender] = block.timestamp;
        emit Staked(msg.sender, amount);
    }

    /// Unstake principal + collect 18% APY reward (pro-rated by time)
    function unstake() external {
        uint256 principal = stakedBalance[msg.sender];
        require(principal > 0, "Nothing staked");

        uint256 duration = block.timestamp - stakeTimestamp[msg.sender];
        uint256 reward = (principal * 18 * duration) / (100 * 365 days);

        stakedBalance[msg.sender] = 0;
        stakeTimestamp[msg.sender] = 0;
        _transfer(address(this), msg.sender, principal);

        if (totalSupply() + reward <= MAX_SUPPLY) {
            _mint(msg.sender, reward);
        }
        emit Unstaked(msg.sender, principal, reward);
    }

    // ── Burn ─────────────────────────────────────────────────────────────────

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // ── View ─────────────────────────────────────────────────────────────────

    /// True if address qualifies for Pro tier (holds + stakes >= 500 OBZ)
    function isPro(address user) external view returns (bool) {
        return balanceOf(user) + stakedBalance[user] >= STAKE_MIN;
    }

    function remainingSupply() external view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
    }

    // ── Owner utils ──────────────────────────────────────────────────────────

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }
}
