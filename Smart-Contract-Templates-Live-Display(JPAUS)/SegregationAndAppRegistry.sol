// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SegregationAndAppRegistry
 * @notice Enforces ecosystem containment and hardcodes payment rules for apps.
 */
contract SegregationAndAppRegistry is AccessControl {
    bytes32 public constant AI_OPERATOR_ROLE = keccak256("AI_OPERATOR_ROLE");
    
    // Core JPAUS Token address — Immutable and completely protected
    address public immutable coreJPAUSToken;

    struct AppUtility {
        uint256 appId;
        address creator;
        address requiredMintToken; // The token that MUST be used to buy this app
        uint256 price;
        bool active;
    }

    uint256 public nextAppId;
    mapping(uint256 => AppUtility) public appRegistry;
    mapping(address => bool) public isAuthorizedSubEngine;

    event SubEngineRegistered(address indexed subEngine);
    event AppCreated(uint256 indexed appId, address indexed requiredMintToken, uint256 price);
    event AppPurchased(uint256 indexed appId, address indexed buyer, address tokenUsed, uint256 amountPaid);

    constructor(address _coreJPAUS, address _admin) {
        coreJPAUSToken = _coreJPAUS;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice Registers secondary engines (AI can only modify secondary engines, never JPAUS core).
     */
    function registerSubEngine(address subEngine) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(subEngine != coreJPAUSToken, "Segregation: Core JPAUS token cannot be modified or added as sub-engine");
        isAuthorizedSubEngine[subEngine] = true;
        emit SubEngineRegistered(subEngine);
    }

    /**
     * @notice Registers a new application tied permanently to its minting token.
     */
    function registerApp(address requiredMintToken, uint256 price) external returns (uint256) {
        uint256 appId = ++nextAppId;
        
        appRegistry[appId] = AppUtility({
            appId: appId,
            creator: msg.sender,
            requiredMintToken: requiredMintToken,
            price: price,
            active: true
        });

        emit AppCreated(appId, requiredMintToken, price);
        return appId;
    }

    /**
     * @notice Enforces hardcoded rule: Apps can ONLY be bought with the token they were minted with.
     */
    function purchaseApp(uint256 appId, address tokenProvided, uint256 amountProvided) external returns (bool) {
        AppUtility storage app = appRegistry[appId];
        require(app.active, "Segregation: Application is not active");
        
        // HARDCODED RULE: Rejects payment if token provided != token minted with
        require(tokenProvided == app.requiredMintToken, "Segregation ERROR: App can ONLY be bought with its original mint token!");
        require(amountProvided >= app.price, "Segregation: Insufficient payment amount");

        bool success = IERC20(tokenProvided).transferFrom(msg.sender, app.creator, app.price);
        require(success, "Segregation: Transfer failed");

        emit AppPurchased(appId, msg.sender, tokenProvided, app.price);
        return true;
    }
}
