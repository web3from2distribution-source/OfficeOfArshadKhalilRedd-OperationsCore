[Contract Address: 0xA95833793234a9fEF98f344b2D04935799e995d5]

// SPDX-License-Identifier: MIT
/*
                        @@@@@@@@@@
                  @@@@@@@     ..  @@@@@@@
              @@@@+ .=    #@@ @@ .   @  @@@@
           @@@-  : @.@.   :         .: @@@  @@@
         @@@  *@@ .    @@@. -=%=          @ @ =@@
       @@@ :   .    @%..  -:= %@@@@@%+     + :@+.@@
      @@. @#-. :.  @#- -@ %=        @@....      +%@@
    @@@  @@  .... @=.#:==*=##+:++:-:     ..... =@  :@@
   @@@      ..... @%- :#:  .:-+*%%-     ... ...     .@@
  @:@  .......... @@ # *%@#@@%*-%%@@@@@ ............  @@
  @@  .........   @@=@@# .: =            .......... . :@
 @@  ............  @@=.=@ -**@@@@+    =.  ............ @@       https://takeapenny.vercel.app
 @@  ...........   .@#: =@=      @@@#*@@@ . .......... .@
@@: ......... ....  @@=*.  %-. .= .-+@.   . ... . .... .@@    Turn "down bad" into "down notsobad"
@%. .........  .     *@*=*:.@@#          .. . ....... . @@
@*                   +. . *=:+@@@*.  .+. ........ ....  @@
@# @ *@@@@-@@+@.#@  #%=##  :  =-+:@@@@@  ........ ....  @@   Exhaustive value tool for EVM/SOL Wallets
@@ *@# @.*@ =..- = *@.  -%@- .. :*-     .....  ....... .@@      that finds EVERY penny in value.
 @.               @@*=#%% .+@@ :.     .             .. .@
 *@  .... ...    @%   .  :@ .#@= @@@@    @@ @@ @ @@ .  @@
  @% ........   @#-#++:=@@ -:.@@*        %@ @@ @ .@   @@
  @@*   ....   @.     #@  :@   @.+  @:.          .   @@@
   @@+  ....  @:.=*#@%- @@. @  -@*#. :- :   :@@     +@@
     @%      @@=@*%*:-*.  @@.@   @+++ =@%:@  .@    @@
      @@.   .% =*@+.@@-.@  =:+@   @:# +  =-+@    -%@
       @@@   @@*    =%%@@#- %-@:. =.=* -@  : @- @@@
         @@@    @@@.    :#@@-%@@*@@@@@- :%@@  =@@
           @@@-    @@@@*.     @@. @  :@@@  @@@@
              @@@@      @@@@@@@@@@.*    #@@@
                 .@@@@@+          =@@@@@+
                        +@@@@@@@@*
*/
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title JUSDVaultToken
 * @notice 1:1 Backed jUSD Token. Users deposit real USDC to mint jUSD.
 * @dev Defaults to Polygon Native USDC (0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359).
 */
contract JUSDVaultToken is ERC20, ReentrancyGuard {
    // Official Polygon PoS Native USDC Contract
    address public constant POLYGON_NATIVE_USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

    IERC20 public immutable usdc;

    event Deposited(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount);

    constructor(address _usdcAddress) ERC20("JPAUS USD Reserve", "jUSD") {
        address targetUsdc = _usdcAddress == address(0) ? POLYGON_NATIVE_USDC : _usdcAddress;
        usdc = IERC20(targetUsdc);
    }

    function decimals() public pure override returns (uint8) {
        return 6; // 6 decimals to match official USDC
    }

    /// @notice Deposit real USDC to mint 1:1 jUSD
    function depositUSDC(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        
        bool success = usdc.transferFrom(msg.sender, address(this), amount);
        require(success, "USDC transfer failed - check allowance");

        _mint(msg.sender, amount);
        emit Deposited(msg.sender, amount);
    }

    /// @notice Burn jUSD to redeem real USDC 1:1
    function redeemUSDC(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient jUSD balance");

        _burn(msg.sender, amount);

        bool success = usdc.transfer(msg.sender, amount);
        require(success, "USDC transfer failed");

        emit Redeemed(msg.sender, amount);
    }
}

/**
 * @title CreatorToken
 * @notice Individual custom token deployed by a creator inside the JPAUS Ecosystem.
 */
contract CreatorToken is ERC20 {
    address public immutable creator;
    address public immutable ecosystemHub;

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address _creator
    ) ERC20(name, symbol) {
        creator = _creator;
        ecosystemHub = msg.sender;
        _mint(_creator, initialSupply);
    }
}

/**
 * @title JPAUSEcosystemHub
 * @notice Central registry for profile activation, token creation, Linktree listings, and order relays.
 * @dev Fee revenues are routed directly to treasury without burning.
 */
contract JPAUSEcosystemHub {
    // Default Fee Treasury Wallet
    address public constant DEFAULT_TREASURY = 0x12c1cb2e979DDcE21330B48bB11db8e62F417150;

    // 6-decimal precision matching jUSD / USDC (1,000,000 micro-units = $1.00)
    uint256 public constant INITIATION_FEE     = 1 * 10**6;   // $1.00 USD profile registration
    uint256 public constant LISTING_FEE        = 100_000;     // $0.10 USD (10 cents) per Linktree listing
    uint256 public constant TOKEN_CREATION_FEE = 1 * 10**6;   // $1.00 USD token deployment fee
    uint256 public constant MIN_TOKEN_DEPOSIT  = 1 * 10**6;   // $1.00 USD minimum reserve deposit
    uint256 public constant TX_FEE_FLAT        = 1000;        // $0.001 USD order relay fee

    IERC20 public immutable backingToken; // jUSD token
    address public treasury;
    address public owner;

    mapping(address => bool) public isProfileActive;
    mapping(address => address[]) public userTokens;

    // Linktree / Wallet Profile Listing Structure
    struct ProfileListing {
        string title;
        string url;
        address linkedWallet;
        uint256 timestamp;
    }

    mapping(address => ProfileListing[]) private profileListings;

    struct Order {
        address buyer;
        address merchant;
        string itemReference;
        uint256 amountPaid;
        uint256 timestamp;
    }

    mapping(address => Order[]) public merchantOrders;

    event ProfileRegistered(address indexed user, uint256 feePaid);
    event ListingAdded(address indexed user, string title, string url, address linkedWallet);
    event TokenCreated(address indexed creator, address indexed tokenAddress, uint256 depositAmount);
    event OrderRelayed(address indexed buyer, address indexed merchant, string itemRef, uint256 amountPaid);
    event TreasuryUpdated(address indexed newTreasury);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not ecosystem owner");
        _;
    }

    constructor(address _backingToken, address _treasury) {
        require(_backingToken != address(0), "Invalid backing token address");
        backingToken = IERC20(_backingToken);
        treasury = _treasury == address(0) ? DEFAULT_TREASURY : _treasury;
        owner = msg.sender;
    }

    /// @notice 1. Initialize a new wallet profile into the JPAUS ecosystem ($1 Gate)
    function registerProfile() external {
        require(!isProfileActive[msg.sender], "Profile already activated");

        bool success = backingToken.transferFrom(msg.sender, treasury, INITIATION_FEE);
        require(success, "Initiation fee transfer failed");

        isProfileActive[msg.sender] = true;
        emit ProfileRegistered(msg.sender, INITIATION_FEE);
    }

    /// @notice 2. Add a Linktree Social/Deal listing (Requires Active Profile + $0.10 jUSD fee)
    function addProfileListing(
        string calldata title,
        string calldata url,
        address linkedWallet
    ) external {
        // TRIGGER MECHANISM: Profile must be active
        require(isProfileActive[msg.sender], "Access Denied: Profile must be active first");

        // CHARGE FEE: $0.10 jUSD directly to treasury
        bool success = backingToken.transferFrom(msg.sender, treasury, LISTING_FEE);
        require(success, "Listing fee transfer failed");

        address walletToLink = linkedWallet == address(0) ? msg.sender : linkedWallet;

        profileListings[msg.sender].push(ProfileListing({
            title: title,
            url: url,
            linkedWallet: walletToLink,
            timestamp: block.timestamp
        }));

        emit ListingAdded(msg.sender, title, url, walletToLink);
    }

    /// @notice Fetch all Linktree listings for a user profile
    function getProfileListings(address user) external view returns (ProfileListing[] memory) {
        return profileListings[user];
    }

    /// @notice 3. Deploy a custom creator token ($1 Creation Fee + $1 or greater Reserve Deposit)
    function createToken(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        uint256 depositAmount
    ) external returns (address) {
        require(isProfileActive[msg.sender], "Must register $1 profile first");
        require(depositAmount >= MIN_TOKEN_DEPOSIT, "Minimum deposit is $1 USD");

        // Transfer $1 Creation Fee to Treasury
        bool feeSuccess = backingToken.transferFrom(msg.sender, treasury, TOKEN_CREATION_FEE);
        require(feeSuccess, "Creation fee transfer failed");

        // Deploy Creator Token
        CreatorToken newToken = new CreatorToken(name, symbol, initialSupply, msg.sender);
        address tokenAddr = address(newToken);

        // Lock $1+ deposit into newly created token address
        bool depositSuccess = backingToken.transferFrom(msg.sender, tokenAddr, depositAmount);
        require(depositSuccess, "Reserve deposit transfer failed");

        userTokens[msg.sender].push(tokenAddr);

        emit TokenCreated(msg.sender, tokenAddr, depositAmount);
        return tokenAddr;
    }

    /// @notice 4. Storefront Order Relay with automatic $0.001 fee deduction
    function relayOrder(address merchant, string calldata itemReference, uint256 paymentAmount) external {
        require(isProfileActive[msg.sender], "Buyer profile inactive");
        require(isProfileActive[merchant], "Merchant profile inactive");
        require(paymentAmount > TX_FEE_FLAT, "Payment amount below minimum transaction fee");

        uint256 netMerchantAmount = paymentAmount - TX_FEE_FLAT;

        // Route $0.001 fee to treasury
        bool feeSuccess = backingToken.transferFrom(msg.sender, treasury, TX_FEE_FLAT);
        require(feeSuccess, "Fee transfer failed");

        // Route net amount to merchant
        bool paySuccess = backingToken.transferFrom(msg.sender, merchant, netMerchantAmount);
        require(paySuccess, "Merchant payment failed");

        merchantOrders[merchant].push(Order({
            buyer: msg.sender,
            merchant: merchant,
            itemReference: itemReference,
            amountPaid: paymentAmount,
            timestamp: block.timestamp
        }));

        emit OrderRelayed(msg.sender, merchant, itemReference, paymentAmount);
    }

    /// @notice Fetch all tokens deployed by a specific profile
    function getUserTokens(address user) external view returns (address[] memory) {
        return userTokens[user];
    }

    /// @notice Update treasury wallet
    function setTreasury(address _newTreasury) external onlyOwner {
        require(_newTreasury != address(0), "Invalid address");
        treasury = _newTreasury;
        emit TreasuryUpdated(_newTreasury);
    }

    /// @notice Emergency recovery function to rescue tokens sent to the contract by accident
    function rescueTokens(address tokenAddress, uint256 amount) external onlyOwner {
        IERC20(tokenAddress).transfer(treasury, amount);
    }
}
