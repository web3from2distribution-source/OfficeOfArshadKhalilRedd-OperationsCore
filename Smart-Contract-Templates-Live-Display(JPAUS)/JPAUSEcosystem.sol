// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC20 Basic Interface for Native USDC & jPAUSD Interactions
 */
interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

/**
 * @title jPAUSD Vault & Token Contract
 * @notice Mints jPAUSD 1:1 against Polygon Native USDC and manages token balances.
 */
contract jPAUSDVault {
    // --- Official On-Chain Metadata ---
    string public name = "jPAUSD Token";
    string public symbol = "jPAUSD";
    uint8 public decimals = 6; // Set to 6 to match Native USDC
    
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    IERC20 public immutable usdcToken;

    // --- Events ---
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Deposited(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount);

    constructor(address _usdcAddress) {
        require(_usdcAddress != address(0), "Invalid USDC address");
        usdcToken = IERC20(_usdcAddress);
    }

    // --- Standard ERC20 Logic ---
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient jPAUSD balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[sender] >= amount, "Insufficient jPAUSD balance");
        require(allowance[sender][msg.sender] >= amount, "Allowance exceeded");
        
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    // --- Vault Core Logic ---

    /// @notice Deposit Native USDC to mint 1:1 jPAUSD
    function depositUSDC(uint256 usdcAmount) external {
        require(usdcAmount > 0, "Amount must be greater than 0");
        require(usdcToken.transferFrom(msg.sender, address(this), usdcAmount), "USDC transfer failed");
        
        balanceOf[msg.sender] += usdcAmount;
        totalSupply += usdcAmount;
        
        emit Transfer(address(0), msg.sender, usdcAmount);
        emit Deposited(msg.sender, usdcAmount);
    }

    /// @notice Redeem jPAUSD 1:1 to withdraw Native USDC
    function redeemUSDC(uint256 jusdAmount) external {
        require(jusdAmount > 0, "Amount must be greater than 0");
        require(balanceOf[msg.sender] >= jusdAmount, "Insufficient jPAUSD balance");
        
        balanceOf[msg.sender] -= jusdAmount;
        totalSupply -= jusdAmount;
        emit Transfer(msg.sender, address(0), jusdAmount);

        require(usdcToken.transfer(msg.sender, jusdAmount), "USDC return transfer failed");
        emit Redeemed(msg.sender, jusdAmount);
    }
}

/**
 * @title Creator Token
 * @notice Deployed automatically by the Ecosystem Hub when a creator launches a new token.
 */
contract CreatorToken {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply, address _creator) {
        name = _name;
        symbol = _symbol;
        totalSupply = _initialSupply;
        balanceOf[_creator] = _initialSupply;
        emit Transfer(address(0), _creator, _initialSupply);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[sender] >= amount, "Insufficient balance");
        require(allowance[sender][msg.sender] >= amount, "Allowance exceeded");
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }
}

/**
 * @title JPAUS Ecosystem Hub
 * @notice Manages user registrations, Link Suite deal listings, and Creator Token deployment.
 */
contract JPAUSEcosystemHub {
    IERC20 public immutable jPAUSDToken;
    address public immutable treasury;

    // --- Fee Structure (6 Decimals: 1,000,000 = 1.0 jPAUSD) ---
    uint256 public constant REGISTRATION_FEE = 1_000_000; // $1.00 jPAUSD
    uint256 public constant LISTING_FEE      = 100_000;   // $0.10 jPAUSD
    uint256 public constant DEPLOYMENT_FEE   = 1_000_000; // $1.00 jPAUSD

    struct Listing {
        string title;
        string url;
        address linkedWallet;
        uint256 timestamp;
    }

    mapping(address => bool) public isProfileActive;
    mapping(address => Listing[]) public profileListings;

    // --- Events ---
    event ProfileRegistered(address indexed user);
    event ListingAdded(address indexed user, string title, string url, address linkedWallet);
    event TokenCreated(address indexed creator, address tokenAddress, string symbol);

    constructor(address _jPAUSDAddress, address _treasury) {
        require(_jPAUSDAddress != address(0), "Invalid jPAUSD address");
        require(_treasury != address(0), "Invalid treasury address");
        jPAUSDToken = IERC20(_jPAUSDAddress);
        treasury = _treasury;
    }

    /// @notice Register a user profile ($1.00 jPAUSD fee)
    function registerProfile() external {
        require(!isProfileActive[msg.sender], "Profile is already activated");
        require(
            jPAUSDToken.transferFrom(msg.sender, treasury, REGISTRATION_FEE),
            "Registration fee transfer failed"
        );
        isProfileActive[msg.sender] = true;
        emit ProfileRegistered(msg.sender);
    }

    /// @notice Add a Link Suite listing ($0.10 jPAUSD fee)
    function addProfileListing(string calldata title, string calldata url, address linkedWallet) external {
        require(isProfileActive[msg.sender], "Must register profile first");
        require(
            jPAUSDToken.transferFrom(msg.sender, treasury, LISTING_FEE),
            "Listing fee transfer failed"
        );

        address walletToLink = linkedWallet == address(0) ? msg.sender : linkedWallet;
        profileListings[msg.sender].push(Listing({
            title: title,
            url: url,
            linkedWallet: walletToLink,
            timestamp: block.timestamp
        }));

        emit ListingAdded(msg.sender, title, url, walletToLink);
    }

    /// @notice Retrieve all Link Suite listings for a given profile
    function getProfileListings(address user) external view returns (Listing[] memory) {
        return profileListings[user];
    }

    /// @notice Deploy a custom Creator Token ($1.00 deployment fee + reserve deposit)
    function createToken(
        string calldata tokenName,
        string calldata tokenSymbol,
        uint256 initialSupply,
        uint256 depositAmount
    ) external returns (address) {
        require(isProfileActive[msg.sender], "Must register profile first");
        require(depositAmount >= 1_000_000, "Minimum reserve deposit is 1.0 jPAUSD");

        uint256 totalCost = DEPLOYMENT_FEE + depositAmount;
        require(
            jPAUSDToken.transferFrom(msg.sender, treasury, totalCost),
            "Fee and deposit transfer failed"
        );

        CreatorToken newToken = new CreatorToken(tokenName, tokenSymbol, initialSupply, msg.sender);
        emit TokenCreated(msg.sender, address(newToken), tokenSymbol);
        return address(newToken);
    }
}
