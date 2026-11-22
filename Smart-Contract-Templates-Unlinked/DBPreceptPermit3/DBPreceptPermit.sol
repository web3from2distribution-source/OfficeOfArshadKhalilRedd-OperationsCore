[Smart-Contract Address: 0xf8e81D47203A594245E36C48e151709F0C19fBe8]

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DBPreceptPermit
 * @notice Core direct on-chain permit contract parameterized around an `owner` address.
 * @dev Uses direct on-chain transactions initiated by `owner` (or an authorized governor)
 *      rather than off-chain EIP-712 signature relays.
 */
contract DBPreceptPermit {
    struct Permit {
        address owner;       // Principal / owner granting the permit
        address delegate;    // Authorized operator / agent / contract
        bytes32 scope;       // Domain-specific action or policy scope hash
        uint256 maxBudget;   // Maximum cumulative units/value allowed under this permit
        uint256 consumed;    // Cumulative units/value consumed so far
        uint64 validAfter;   // Earliest active timestamp (0 = active immediately upon issuance)
        uint64 expiresAt;    // Expiration timestamp (must be greater than block.timestamp & validAfter)
        uint256 nonce;       // Per-owner sequence nonce for unique permit derivation
        bool revoked;        // True if revoked by owner or governor
    }

    /// @notice Mapping from permitId => Permit record
    mapping(bytes32 => Permit) private _permits;

    /// @notice Current sequential nonce per owner address
    mapping(address => uint256) public nonces;

    /// @notice Optional administrative/clearing governor address
    address public governor;

    event GovernorUpdated(address indexed previousGovernor, address indexed newGovernor);

    event PermitCreated(
        bytes32 indexed permitId,
        address indexed owner,
        address indexed delegate,
        bytes32 scope,
        uint256 maxBudget,
        uint64 validAfter,
        uint64 expiresAt,
        uint256 nonce
    );

    event PermitConsumed(
        bytes32 indexed permitId,
        address indexed caller,
        uint256 amount,
        uint256 remainingBudget
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
    error NotOwnerOrGovernor();
    error NotDelegateOrGovernor();
    error PermitRevokedError();
    error PermitNotActiveYet(uint64 currentTime, uint64 validAfter);
    error PermitExpiredError(uint64 currentTime, uint64 expiresAt);
    error ScopeMismatch(bytes32 expectedScope, bytes32 providedScope);
    error BudgetExceeded(uint256 requested, uint256 remaining);

    constructor(address initialGovernor) {
        governor = initialGovernor;
        emit GovernorUpdated(address(0), initialGovernor);
    }

    /**
     * @notice Updates the governor address (callable by current governor if set).
     */
    function setGovernor(address newGovernor) external {
        if (governor != address(0) && msg.sender != governor) {
            revert NotOwnerOrGovernor();
        }
        if (newGovernor == address(0)) revert ZeroAddress();
        address prev = governor;
        governor = newGovernor;
        emit GovernorUpdated(prev, newGovernor);
    }

    /**
     * @notice Computes a deterministic permit ID for a given `owner` and parameters.
     */
    function computePermitId(
        address owner,
        address delegate,
        bytes32 scope,
        uint256 maxBudget,
        uint64 validAfter,
        uint64 expiresAt,
        uint256 nonce
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                owner,
                delegate,
                scope,
                maxBudget,
                validAfter,
                expiresAt,
                nonce
            )
        );
    }

    /**
     * @notice Issues a new permit directly on-chain from `msg.sender` as `owner`.
     */
    function issuePermit(
        address delegate,
        bytes32 scope,
        uint256 maxBudget,
        uint64 validAfter,
        uint64 expiresAt
    ) external returns (bytes32 permitId) {
        address owner = msg.sender;
        if (delegate == address(0)) revert ZeroAddress();
        if (maxBudget == 0) revert InvalidAmount();
        if (expiresAt <= block.timestamp || expiresAt <= validAfter) {
            revert InvalidWindow(validAfter, expiresAt);
        }

        uint256 currentNonce = nonces[owner];
        nonces[owner] = currentNonce + 1;

        permitId = computePermitId(
            owner,
            delegate,
            scope,
            maxBudget,
            validAfter,
            expiresAt,
            currentNonce
        );

        if (_permits[permitId].owner != address(0)) {
            revert PermitAlreadyExists(permitId);
        }

        _permits[permitId] = Permit({
            owner: owner,
            delegate: delegate,
            scope: scope,
            maxBudget: maxBudget,
            consumed: 0,
            validAfter: validAfter,
            expiresAt: expiresAt,
            nonce: currentNonce,
            revoked: false
        });

        emit PermitCreated(
            permitId,
            owner,
            delegate,
            scope,
            maxBudget,
            validAfter,
            expiresAt,
            currentNonce
        );
    }

    /**
     * @notice Consumes budget against an active direct on-chain permit.
     */
    function consumePermit(
        bytes32 permitId,
        bytes32 expectedScope,
        uint256 amount
    ) external returns (uint256 remainingBudget) {
        Permit storage p = _permits[permitId];
        if (p.owner == address(0)) revert PermitNotFound(permitId);
        if (p.revoked) revert PermitRevokedError();
        if (msg.sender != p.delegate && msg.sender != governor) {
            revert NotDelegateOrGovernor();
        }
        if (p.scope != expectedScope) {
            revert ScopeMismatch(p.scope, expectedScope);
        }
        if (amount == 0) revert InvalidAmount();

        uint64 nowTs = uint64(block.timestamp);
        if (p.validAfter != 0 && nowTs < p.validAfter) {
            revert PermitNotActiveYet(nowTs, p.validAfter);
        }
        if (nowTs >= p.expiresAt) {
            revert PermitExpiredError(nowTs, p.expiresAt);
        }

        uint256 remaining = p.maxBudget - p.consumed;
        if (amount > remaining) {
            revert BudgetExceeded(amount, remaining);
        }

        p.consumed += amount;
        remainingBudget = p.maxBudget - p.consumed;

        emit PermitConsumed(permitId, msg.sender, amount, remainingBudget);
    }

    /**
     * @notice Revokes a permit immediately so no further consumption can occur.
     */
    function revokePermit(bytes32 permitId) external {
        Permit storage p = _permits[permitId];
        if (p.owner == address(0)) revert PermitNotFound(permitId);
        if (msg.sender != p.owner && msg.sender != governor) {
            revert NotOwnerOrGovernor();
        }
        if (!p.revoked) {
            p.revoked = true;
            emit PermitRevoked(permitId, msg.sender, uint64(block.timestamp));
        }
    }

    /**
     * @notice Checks whether a permit is currently active and able to cover `amount` under `expectedScope`.
     */
    function isPermitActive(
        bytes32 permitId,
        bytes32 expectedScope,
        uint256 amount
    ) external view returns (bool active, string memory reason) {
        Permit storage p = _permits[permitId];
        if (p.owner == address(0)) return (false, "NOT_FOUND");
        if (p.revoked) return (false, "REVOKED");
        if (p.scope != expectedScope) return (false, "SCOPE_MISMATCH");
        if (amount == 0) return (false, "ZERO_AMOUNT");

        uint64 nowTs = uint64(block.timestamp);
        if (p.validAfter != 0 && nowTs < p.validAfter) return (false, "NOT_YET_ACTIVE");
        if (nowTs >= p.expiresAt) return (false, "EXPIRED");
        if (amount > p.maxBudget - p.consumed) return (false, "BUDGET_EXCEEDED");

        return (true, "ACTIVE");
    }

    /**
     * @notice Returns full permit details for a given `permitId`.
     */
    function getPermit(bytes32 permitId) external view returns (Permit memory) {
        Permit memory p = _permits[permitId];
        if (p.owner == address(0)) revert PermitNotFound(permitId);
        return p;
    }
}
