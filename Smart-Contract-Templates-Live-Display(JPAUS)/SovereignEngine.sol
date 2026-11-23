// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ISwapRouter02 {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

/**
 * @title SovereignMemoryAndSubscriptionEngine
 * @notice Integrated Base44 web app backend contract handling:
 *         1. Wallet-based profile creation and memory anchoring.
 *         2. Automated crypto subscription processing (splitting fees and routing PYUSD).
 *         3. Unrestricted (open) memory access tied directly to the connected user's wallet profile.
 */
contract SovereignMemoryAndSubscriptionEngine {
    address public immutable deployerWallet;
    address public immutable base44Treasury;
    address public immutable swapRouter;
    address public immutable jpausToken;
    address public immutable pyusdToken;

    uint256 public constant OPERATIONAL_FEE_JPAUSD = 235 * 1016; // $2.35 operational fee scaled

    struct UserProfile {
        bool isCreated;
        uint256 subscriptionExpiration;
        string memoryCid;
    }

    mapping(address => UserProfile) public profiles;

    event ProfileCreated(address indexed user);
    event MemoryUpdated(address indexed user, string memoryCid);
    event CryptoSubscriptionProcessed(address indexed user, uint256 feePaid, uint256 pyusdRouted);

    error Unauthorized();
    error ProfileNotYetCreated();
    error TransferFailed();
    error SwapFailed();

    constructor(
        address _base44Treasury,
        address _swapRouter,
        address _jpaus,
        address _pyusd
    ) {
        deployerWallet = msg.sender;
        base44Treasury = _base44Treasury;
        swapRouter = _swapRouter;
        jpausToken = _jpaus;
        pyusdToken = _pyusd;
    }

    /**
     * @notice Step 1: User connects wallet and creates their on-chain Base44 profile.
     */
    function createProfile() external {
        if (profiles[msg.sender].isCreated) revert Unauthorized();
        profiles[msg.sender].isCreated = true;
        emit ProfileCreated(msg.sender);
    }

    /**
     * @notice Step 2: Automatically handles crypto subscription payments, splits the fee, 
     *         swaps the remainder to PYUSD for Base44, and updates the user's effective memory log.
     */
    function processSubscriptionAndSaveMemory(
        uint256 baseSubscriptionAmount,
        bytes calldata swapPath,
        string calldata newMemoryCid
    ) external returns (uint256 pyusdOutput) {
        if (!profiles[msg.sender].isCreated) revert ProfileNotYetCreated();

        uint256 totalCost = baseSubscriptionAmount + OPERATIONAL_FEE_JPAUSD;

        // Pull full crypto payment from connected wallet
        bool success = IERC20(jpausToken).transferFrom(msg.sender, address(this), totalCost);
        if (!success) revert TransferFailed();

        // Instant middleman split fee to deployer
        bool feeSuccess = IERC20(jpausToken).transfer(deployerWallet, OPERATIONAL_FEE_JPAUSD);
        if (!feeSuccess) revert TransferFailed();

        // Swap subscription tokens to PYUSD and route to Base44 treasury
        IERC20(jpausToken).approve(swapRouter, baseSubscriptionAmount);
        
        ISwapRouter02.ExactInputParams memory params = ISwapRouter02.ExactInputParams({
            path: swapPath,
            recipient: base44Treasury,
            amountIn: baseSubscriptionAmount,
            amountOutMinimum: 1
        });

        pyusdOutput = ISwapRouter02(swapRouter).exactInput(params);
        if (pyusdOutput == 0) revert SwapFailed();

        // Update profile memory log (left open/unbarred for the connected wallet owner)
        profiles[msg.sender].memoryCid = newMemoryCid;
        profiles[msg.sender].subscriptionExpiration = block.timestamp + 30 days;

        emit CryptoSubscriptionProcessed(msg.sender, OPERATIONAL_FEE_JPAUSD, pyusdOutput);
        emit MemoryUpdated(msg.sender, newMemoryCid);
    }

    /**
     * @notice Direct wallet read function: Any connected wallet can immediately view 
     *         their own saved memory logs without artificial gating.
     */
    function getMyMemoryLog(address user) external view returns (string memory memoryCid, uint256 expiration, bool activeProfile) {
        UserProfile memory profile = profiles[user];
        return (profile.memoryCid, profile.subscriptionExpiration, profile.isCreated);
    }
}
