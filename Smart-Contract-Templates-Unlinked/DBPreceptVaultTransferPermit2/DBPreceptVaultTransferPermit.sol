[Smart-Contract Address: 0xd8b934580fcE35a11B58C6D73aDeE468a2833fa8]

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DBPreceptVaultTransferPermit
 * @notice Standalone direct on-chain vault transfer permit template.
 * @dev Self-contained template with direct on-chain issuance and no external
 *      contract calls or automated off-chain triggers.
 */
contract DBPreceptVaultTransferPermit {
    struct TransferPermit {
        address grantor;     // Principal / owner granting vault transfer permission
        address agent;       // Authorized agent or operator permitted to use the permit
        address vault;       // Referenced vault address in the permit record
        address asset;       // Referenced asset address (address(0) for native token)
        address recipient;   // Target recipient (address(0) if any non-zero recipient is allowed)
        uint256 maxAmount;   // Maximum cumulative amount allowed under this permit
        uint256 transferred; // Cumulative amount recorded against this permit
        uint64 validAfter;   // Earliest active timestamp (0 = active immediately)
        uint64 expiresAt;    // Expiration timestamp (must exceed current time and validAfter)
        uint256 nonce;       // Grantor sequence nonce for unique permit IDs
        bool revoked;        // True if revoked prior to expiration
    }

    mapping(bytes32 => TransferPermit) private _permits;
    mapping(address => uint256) public nonces;

    address public clearingController;

    event ControllerUpdated(address indexed previousController, address indexed newController);

    event PermitIssued(
        bytes32 indexed permitId,
        address indexed grantor,
        address indexed agent,
        address vault,
        address asset,
        address recipient,
        uint256 maxAmount,
        uint64 validAfter,
        uint64 expiresAt,
        uint256 nonce
    );

    event TransferRecorded(
        bytes32 indexed permitId,
        address indexed agent,
        address indexed recipient,
        uint256 amount,
        uint256 remainingAllowance
    );

    event PermitRevoked(
        bytes32 indexed permitId,
        address indexed revokedBy,
        uint64 revokedAt
    );

    error ZeroAddress();
    error InvalidAmount();
    error InvalidWindow(uint64 validAfter, uint64 expiresAt);
    error PermitAlreadyExists(bytes32 permitId);
    error PermitNotFound(bytes32 permitId);
    error NotGrantorOrController();
    error NotPermittedAgent();
    error PermitIsRevoked();
    error PermitNotYetActive(uint64 currentTime, uint64 validAfter);
    error PermitExpired(uint64 currentTime, uint64 expiresAt);
    error RecipientMismatch(address expected, address actual);
    error AllowanceExceeded(uint256 requested, uint256 remaining);

    constructor(address initialController) {
        clearingController = initialController;
        emit ControllerUpdated(address(0), initialController);
    }

    /**
     * @notice Updates the clearingController address (callable by current controller if set).
     */
    function setClearingController(address newController) external {
        if (clearingController != address(0) && msg.sender != clearingController) {
            revert NotGrantorOrController();
        }
        if (newController == address(0)) revert ZeroAddress();

        address previousController = clearingController;
        clearingController = newController;
        emit ControllerUpdated(previousController, newController);
    }

    /**
     * @notice Computes a deterministic permit ID from permit parameters and grantor nonce.
     */
    function computePermitId(
        address grantor,
        address agent,
        address vault,
        address asset,
        address recipient,
        uint256 maxAmount,
        uint64 validAfter,
        uint64 expiresAt,
        uint256 nonce
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                grantor,
                agent,
                vault,
                asset,
                recipient,
                maxAmount,
                validAfter,
                expiresAt,
                nonce
            )
        );
    }

    /**
     * @notice Issues a new direct on-chain vault transfer permit from `msg.sender`.
     */
    function issuePermit(
        address agent,
        address vault,
        address asset,
        address recipient,
        uint256 maxAmount,
        uint64 validAfter,
        uint64 expiresAt
    ) external returns (bytes32 permitId) {
        if (agent == address(0) || vault == address(0)) revert ZeroAddress();
        if (maxAmount == 0) revert InvalidAmount();

        uint64 nowTs = uint64(block.timestamp);
        if (expiresAt <= nowTs || expiresAt <= validAfter) {
            revert InvalidWindow(validAfter, expiresAt);
        }

        uint256 currentNonce = nonces[msg.sender];
        nonces[msg.sender] = currentNonce + 1;

        permitId = computePermitId(
            msg.sender,
            agent,
            vault,
            asset,
            recipient,
            maxAmount,
            validAfter,
            expiresAt,
            currentNonce
        );

        if (_permits[permitId].grantor != address(0)) {
            revert PermitAlreadyExists(permitId);
        }

        _permits[permitId] = TransferPermit({
            grantor: msg.sender,
            agent: agent,
            vault: vault,
            asset: asset,
            recipient: recipient,
            maxAmount: maxAmount,
            transferred: 0,
            validAfter: validAfter,
            expiresAt: expiresAt,
            nonce: currentNonce,
            revoked: false
        });

        emit PermitIssued(
            permitId,
            msg.sender,
            agent,
            vault,
            asset,
            recipient,
            maxAmount,
            validAfter,
            expiresAt,
            currentNonce
        );
    }

    /**
     * @notice Records `amount` transferred to `actualRecipient` against the permit's allowance.
     */
    function consumeTransfer(
        bytes32 permitId,
        address actualRecipient,
        uint256 amount
    ) external returns (uint256 remainingAllowance) {
        TransferPermit storage p = _permits[permitId];
        if (p.grantor == address(0)) revert PermitNotFound(permitId);
        if (p.revoked) revert PermitIsRevoked();
        if (msg.sender != p.agent && msg.sender != clearingController) {
            revert NotPermittedAgent();
        }
        if (amount == 0) revert InvalidAmount();
        if (actualRecipient == address(0)) revert ZeroAddress();
        if (p.recipient != address(0) && p.recipient != actualRecipient) {
            revert RecipientMismatch(p.recipient, actualRecipient);
        }

        uint64 nowTs = uint64(block.timestamp);
        if (p.validAfter != 0 && nowTs < p.validAfter) {
            revert PermitNotYetActive(nowTs, p.validAfter);
        }
        if (nowTs >= p.expiresAt) {
            revert PermitExpired(nowTs, p.expiresAt);
        }

        uint256 remaining = p.maxAmount - p.transferred;
        if (amount > remaining) {
            revert AllowanceExceeded(amount, remaining);
        }

        p.transferred += amount;
        remainingAllowance = p.maxAmount - p.transferred;

        emit TransferRecorded(permitId, msg.sender, actualRecipient, amount, remainingAllowance);
    }

    /**
     * @notice Revokes an active permit so no further transfer usage can be recorded.
     */
    function revokePermit(bytes32 permitId) external {
        TransferPermit storage p = _permits[permitId];
        if (p.grantor == address(0)) revert PermitNotFound(permitId);
        if (msg.sender != p.grantor && msg.sender != clearingController) {
            revert NotGrantorOrController();
        }

        if (!p.revoked) {
            p.revoked = true;
            emit PermitRevoked(permitId, msg.sender, uint64(block.timestamp));
        }
    }

    /**
     * @notice Checks whether a permit is currently valid for `actualRecipient` and `amount`.
     */
    function isPermitValid(
        bytes32 permitId,
        address actualRecipient,
        uint256 amount
    ) external view returns (bool valid, string memory reason) {
        TransferPermit storage p = _permits[permitId];
        if (p.grantor == address(0)) return (false, "PERMIT_NOT_FOUND");
        if (p.revoked) return (false, "PERMIT_REVOKED");
        if (amount == 0) return (false, "ZERO_AMOUNT");
        if (actualRecipient == address(0)) return (false, "ZERO_RECIPIENT");
        if (p.recipient != address(0) && p.recipient != actualRecipient) {
            return (false, "RECIPIENT_MISMATCH");
        }

        uint64 nowTs = uint64(block.timestamp);
        if (p.validAfter != 0 && nowTs < p.validAfter) return (false, "NOT_YET_ACTIVE");
        if (nowTs >= p.expiresAt) return (false, "EXPIRED");
        if (amount > p.maxAmount - p.transferred) return (false, "ALLOWANCE_EXCEEDED");

        return (true, "VALID");
    }

    /**
     * @notice Returns the full permit struct for `permitId`.
     */
    function getPermit(bytes32 permitId) external view returns (TransferPermit memory) {
        TransferPermit memory p = _permits[permitId];
        if (p.grantor == address(0)) revert PermitNotFound(permitId);
        return p;
    }
}
