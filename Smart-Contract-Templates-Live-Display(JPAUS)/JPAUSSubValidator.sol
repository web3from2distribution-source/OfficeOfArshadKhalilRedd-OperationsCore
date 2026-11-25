// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IMasterValidator {
    function isValidated(address user) external view returns (bool);
}

/**
 * @notice Individual Sub-Validator Gateway deployed per user via the Factory.
 * Independent access: users only need to pass THIS contract's payment gate, 
 * without needing re-validation back at the master layer.
 */
contract JPAUSCommunitySubValidator {
    address public creator;
    address public paymentToken; // JPAUSD or an approved 6-decimal child token
    uint256 public customFee;     // Fee set by the creator in 6-decimal format
    
    mapping(address => bool) public subAuthorized;

    event SubAccessGranted(address indexed user, uint256 feePaid, address creatorTreasury);

    constructor(address _creator, address _paymentToken, uint256 _customFee) {
        creator = _creator;
        paymentToken = _paymentToken;
        customFee = _customFee;
    }

    /**
     * @notice Users pay the creator's designated fee using JPAUSD (or child token) 
     * to unlock access to this specific sub-validator zone.
     */
    function payAndAccess() external {
        require(!subAuthorized[msg.sender], "Already authorized on this sub-validator");

        // Pull custom fee directly to the creator's wallet address
        bool success = IERC20(paymentToken).transferFrom(msg.sender, creator, customFee);
        require(success, "Sub-validator token payment failed");

        subAuthorized[msg.sender] = true;
        emit SubAccessGranted(msg.sender, customFee, creator);
    }

    // Creator manual override if needed
    function grantAccessManually(address user, bool status) external {
        require(msg.sender == creator, "Only sub-validator creator can manage");
        subAuthorized[user] = status;
    }
}

/**
 * @notice Factory contract accessible exclusively by wallets validated on the Master Validator.
 */
contract JPAUSSubValidatorFactory {
    address public immutable masterValidator;
    address public immutable defaultJPAUSToken;

    // Track all deployed sub-validators by creator
    mapping(address => address[]) public userDeployedSubValidators;
    address[] public allSubValidators;

    event SubValidatorCreated(address indexed creator, address subValidatorAddress, uint256 fee);

    constructor(address _masterValidator, address _jpausToken) {
        masterValidator = _masterValidator;
        defaultJPAUSToken = _jpausToken;
    }

    /**
     * @notice Master-validated users can invoke this to spin up their own sub-validator gateway.
     */
    function deploySubValidator(uint256 _customFee) external returns (address) {
        // Requirement #1 & #2: Must be validated by the Master Validator first
        bool isMasterValid = IMasterValidator(masterValidator).isValidated(msg.sender);
        require(isMasterValid, "Must complete Master Validation before deploying a sub-validator");

        // Deploy a new instance of the community sub-validator using JPAUSD/child token
        JPAUSCommunitySubValidator newSub = new JPAUSCommunitySubValidator(
            msg.sender, 
            defaultJPAUSToken, 
            _customFee
        );

        address subAddress = address(newSub);
        userDeployedSubValidators[msg.sender].push(subAddress);
        allSubValidators.push(subAddress);

        emit SubValidatorCreated(msg.sender, subAddress, _customFee);
        return subAddress;
    }

    function getUserSubValidators(address user) external view returns (address[] memory) {
        return userDeployedSubValidators[user];
    }
}
