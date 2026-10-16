// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IPancakeRouter02 {
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

/**
 * @title OBZ Fee Router
 * @notice Swap router that forwards trades to PancakeSwap while charging a 1%
 *         platform fee to the admin fee wallet and enforcing a per-wallet
 *         daily swap quota measured in USDT (OBZ counts 1:1 by design).
 */
contract OBZFeeRouter is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IPancakeRouter02 public immutable pancakeRouter;
    address public immutable WBNB;
    address public immutable usdtToken;
    address public immutable obzToken;

    address public feeWallet;

    uint256 public constant FEE_BPS = 100; // 1%
    uint256 public constant BPS = 10_000;

    uint256 public dailyLimitUsdt = 10 * 1e18; // 10 USDT per wallet per UTC day

    // user => dayIndex => swapped value in USDT
    mapping(address => mapping(uint256 => uint256)) public dailyUsedUsdt;
    // dayIndex => platform-wide swapped value in USDT
    mapping(uint256 => uint256) public dailyTotalUsdt;

    event SwapWithFee(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 feeAmount,
        uint256 usdtValue,
        uint256 dayIndex
    );
    event FeeWalletChanged(address indexed wallet);
    event DailyLimitChanged(uint256 limitUsdt);

    constructor(
        address router_,
        address usdt_,
        address obz_,
        address wbnb_,
        address feeWallet_
    ) Ownable(msg.sender) {
        require(router_ != address(0) && usdt_ != address(0) && obz_ != address(0), "zero address");
        require(wbnb_ != address(0) && feeWallet_ != address(0), "zero address");
        pancakeRouter = IPancakeRouter02(router_);
        usdtToken = usdt_;
        obzToken = obz_;
        WBNB = wbnb_;
        feeWallet = feeWallet_;
    }

    // ── ADMIN ───────────────────────────────────────────────────────────────

    function setFeeWallet(address wallet) external onlyOwner {
        require(wallet != address(0), "zero address");
        feeWallet = wallet;
        emit FeeWalletChanged(wallet);
    }

    function setDailyLimitUsdt(uint256 limitUsdt) external onlyOwner {
        require(limitUsdt > 0, "zero limit");
        dailyLimitUsdt = limitUsdt;
        emit DailyLimitChanged(limitUsdt);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ── VIEWS ───────────────────────────────────────────────────────────────

    function currentDay() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function getQuota(address user)
        external
        view
        returns (uint256 used, uint256 remaining, uint256 limit, uint256 resetsAt)
    {
        uint256 day = currentDay();
        used = dailyUsedUsdt[user][day];
        limit = dailyLimitUsdt;
        remaining = used < limit ? limit - used : 0;
        resetsAt = (day + 1) * 1 days;
    }

    function todayVolumeUsdt() external view returns (uint256) {
        return dailyTotalUsdt[currentDay()];
    }

    /// UI helper: quote a swap before sending it.
    function quoteSwap(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256 feeAmount, uint256 amountInNet, uint256 expectedOut, uint256 usdtValue)
    {
        require(path.length >= 2, "bad path");
        feeAmount = (amountIn * FEE_BPS) / BPS;
        amountInNet = amountIn - feeAmount;
        uint256[] memory amounts = pancakeRouter.getAmountsOut(amountInNet, path);
        expectedOut = amounts[amounts.length - 1];
        usdtValue = _usdtValue(path[0], path[path.length - 1], amountIn, expectedOut);
    }

    // ── SWAPS ───────────────────────────────────────────────────────────────

    function swapExactTokensForTokensWithFee(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (uint256[] memory amounts) {
        require(path.length >= 2, "bad path");
        address tokenIn = path[0];
        uint256 fee = (amountIn * FEE_BPS) / BPS;
        uint256 net = amountIn - fee;

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 value = _quoteUsdtValue(tokenIn, path[path.length - 1], amountIn, net, path);
        _enforceAndRecord(msg.sender, value);

        IERC20(tokenIn).safeTransfer(feeWallet, fee);
        IERC20(tokenIn).safeIncreaseAllowance(address(pancakeRouter), net);

        amounts = pancakeRouter.swapExactTokensForTokens(net, amountOutMin, path, msg.sender, deadline);
        emit SwapWithFee(msg.sender, tokenIn, path[path.length - 1], amountIn, fee, value, currentDay());
    }

    function swapExactETHForTokensWithFee(
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external payable nonReentrant whenNotPaused returns (uint256[] memory amounts) {
        require(path.length >= 2, "bad path");
        require(path[0] == WBNB, "path must start with WBNB");

        uint256 fee = (msg.value * FEE_BPS) / BPS;
        uint256 net = msg.value - fee;

        uint256 value = _quoteUsdtValue(WBNB, path[path.length - 1], msg.value, net, path);
        _enforceAndRecord(msg.sender, value);

        (bool ok, ) = feeWallet.call{value: fee}("");
        require(ok, "fee transfer failed");

        amounts = pancakeRouter.swapExactETHForTokens{value: net}(amountOutMin, path, msg.sender, deadline);
        emit SwapWithFee(msg.sender, WBNB, path[path.length - 1], msg.value, fee, value, currentDay());
    }

    function swapExactTokensForETHWithFee(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (uint256[] memory amounts) {
        require(path.length >= 2, "bad path");
        address tokenIn = path[0];
        uint256 fee = (amountIn * FEE_BPS) / BPS;
        uint256 net = amountIn - fee;

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 value = _quoteUsdtValue(tokenIn, WBNB, amountIn, net, path);
        _enforceAndRecord(msg.sender, value);

        IERC20(tokenIn).safeTransfer(feeWallet, fee);
        IERC20(tokenIn).safeIncreaseAllowance(address(pancakeRouter), net);

        amounts = pancakeRouter.swapExactTokensForETH(net, amountOutMin, path, msg.sender, deadline);
        emit SwapWithFee(msg.sender, tokenIn, WBNB, amountIn, fee, value, currentDay());
    }

    // ── INTERNAL ────────────────────────────────────────────────────────────

    function _enforceAndRecord(address user, uint256 usdtValue) internal {
        uint256 day = currentDay();
        uint256 used = dailyUsedUsdt[user][day] + usdtValue;
        require(used <= dailyLimitUsdt, "daily swap limit reached (10 USDT/day)");
        dailyUsedUsdt[user][day] = used;
        dailyTotalUsdt[day] += usdtValue;
    }

    function _quoteUsdtValue(
        address tokenIn,
        address tokenOut,
        uint256 amountInFull,
        uint256 amountInNet,
        address[] calldata path
    ) internal view returns (uint256) {
        if (tokenIn == usdtToken || tokenIn == obzToken) return amountInFull;
        if (tokenIn == WBNB) return _quoteToUsdt(amountInFull);
        if (tokenOut == usdtToken || tokenOut == obzToken) return _expectedOut(amountInNet, path);
        revert("unsupported pair for quota pricing");
    }

    function _usdtValue(address tokenIn, address tokenOut, uint256 amountIn, uint256 expectedOut)
        internal
        view
        returns (uint256)
    {
        if (tokenIn == usdtToken || tokenIn == obzToken) return amountIn;
        if (tokenIn == WBNB) return _quoteToUsdt(amountIn);
        if (tokenOut == usdtToken || tokenOut == obzToken) return expectedOut;
        revert("unsupported pair for quota pricing");
    }

    function _quoteToUsdt(uint256 bnbAmount) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = usdtToken;
        uint256[] memory amounts = pancakeRouter.getAmountsOut(bnbAmount, path);
        return amounts[1];
    }

    function _expectedOut(uint256 amountInNet, address[] calldata path) internal view returns (uint256) {
        uint256[] memory amounts = pancakeRouter.getAmountsOut(amountInNet, path);
        return amounts[amounts.length - 1];
    }
}
