[Smart-Contract Address: 0x358AA13c52544ECCEF6B0ADD0f801012ADAD5eE3]

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DBPreceptDerivativeMintPermit
 * @notice Standalone direct on-chain derivative minting permit template.
 * @dev Written as a self-contained template with direct on-chain issuance and
 *      no external contract dependencies or automated off-chain hooks.
 */
contract DBPreceptDerivativeMintPermit {
    struct DerivativeMintPermit {
        address issuer;            // Principal / authority issuing the mint permit
        address minter;            // Permitted minter / operator / AI agent address
        address derivativeContract;// Target derivative contract (address(0) if open)
        bytes32 seriesHash;        // Derivative series, underlying, or class identifier hash
        uint256 maxMintAmount;     // Maximum cumulative derivative units/amount allowed
        uint256 mintedAmount;      // Cumulative derivative units/amount recorded so far
        uint64 validAfter;         // Earliest active timestamp (0 = active immediately)
        uint64 expiresAt;          // Expiration timestamp (must exceed block.timestamp & validAfter)
        uint256 nonce;             // Per-issuer sequence nonce
        bool revoked;              // True if revoked prior to expiration
    }

    /// @notice Mapping from permitId => DerivativeMintPermit record
    mapping(bytes32 => DerivativeMintPermit) private _permits;

    /// @notice Current sequential nonce per issuer address
    mapping(address => uint256) public nonces;

    /// @notice Optional administrative/clearing minter-controller address
    address public minterController;

    event MinterControllerUpdated(
        address indexed previousController,
        address indexed newController
    );

    event DerivativeMintPermitIssued(
        bytes32 indexed permitId,
        address indexed issuer,
        address indexed minter,
        address derivativeContract,
        bytes32 seriesHash,
        uint256 maxMintAmount,
        uint64 validAfter,
        uint64 expiresAt,
        uint256 nonce
    );

    event DerivativeMintRecorded(
        bytes32 indexed permitId,
        address indexed caller,
        address indexed derivativeContract,
        bytes32 seriesHash,
        uint256 amount,
        uint256 remainingMintAmount
    );

    event DerivativeMintPermitRevoked(
        bytes32 indexed permitId,
        address indexed revokedBy,
        uint64 revokedAt
    );

    error ZeroAddress();
    error InvalidMintAmount();
    error InvalidWindow(uint64 validAfter, uint64 expiresAt);
    error PermitAlreadyExists(bytes32 permitId);
    error PermitNotFound(bytes32 permitId);
    error NotIssuerOrController();
    error NotMinterOrController();
    error PermitRevokedError();
    error PermitNotActiveYet(uint64 currentTime, uint64 validAfter);
    error PermitExpiredError(uint64 currentTime, uint64 expiresAt);
    error DerivativeContractMismatch(address expectedContract, address actualContract);
    error SeriesMismatch(bytes32 expectedSeries, bytes32 actualSeries);
    error MintCapExceeded(uint256 requested, uint256 remaining);

    constructor(address initialController) {
        minterController = initialController;
        emit MinterControllerUpdated(address(0), initialController);
    }

    /**
     * @notice Updates the minterController address (callable by current controller if set).
     */
    function setMinterController(address newController) external {
        if (minterController != address(0) && msg.sender != minterController) {
            revert NotIssuerOrController();
        }
        if (newController == address(0)) revert ZeroAddress();
        address prev = minterController;
        minterController = newController;
        emit MinterControllerUpdated(prev, newController);
    }

    /**
     * @notice Computes a deterministic permit ID for a derivative mint permit.
     */
    function computePermitId(
        address issuer,
        address minter,
        address derivativeContract,
        bytes32 seriesHash,
        uint256 maxMintAmount,
        uint64 validAfter,
        uint64 expiresAt,
        uint256 nonce
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                issuer,
                minter,
                derivativeContract,
                seriesHash,
                maxMintAmount,
                validAfter,
                expiresAt,
                nonce
            )
        );
    }

    /**
     * @notice Issues a new direct on-chain derivative mint permit from `msg.sender`.
     */
    function issueDerivativeMintPermit(
        address minter,
        address derivativeContract,
        bytes32 seriesHash,
        uint256 maxMintAmount,
        uint64 validAfter,
        uint64 expiresAt
    ) external returns (bytes32 permitId) {
        address issuer = msg.sender;
        if (minter == address(0)) revert ZeroAddress();
        if (maxMintAmount == 0) revert InvalidMintAmount();
        if (expiresAt <= block.timestamp || expiresAt <= validAfter) {
            revert InvalidWindow(validAfter, expiresAt);
        }

        uint256 currentNonce = nonces[issuer];
        nonces[issuer] = currentNonce + 1;

        permitId = computePermitId(
            issuer,
            minter,
            derivativeContract,
            seriesHash,
            maxMintAmount,
            validAfter,
            expiresAt,
            currentNonce
        );

        if (_permits[permitId].issuer != address(0)) {
            revert PermitAlreadyExists(permitId);
        }

        _permits[permitId] = DerivativeMintPermit({
            issuer: issuer,
            minter: minter,
            derivativeContract: derivativeContract,
            seriesHash: seriesHash,
            maxMintAmount: maxMintAmount,
            mintedAmount: 0,
            validAfter: validAfter,
            expiresAt: expiresAt,
            nonce: currentNonce,
            revoked: false
        });

        emit DerivativeMintPermitIssued(
            permitId,
            issuer,
            minter,
            derivativeContract,
            seriesHash,
            maxMintAmount,
            validAfter,
            expiresAt,
            currentNonce
        );
    }

    /**
     * @notice Records `amount` of derivative minting against an active permit.
     */
    function consumeMintPermit(
        bytes32 permitId,
        address actualDerivativeContract,
        bytes32 actualSeriesHash,
        uint256 amount
    ) external returns (uint256 remainingMintAmount) {
        DerivativeMintPermit storage p = _permits[permitId];
        if (p.issuer == address(0)) revert PermitNotFound(permitId);
        if (p.revoked) revert PermitRevokedError();
        if (msg.sender != p.minter && msg.sender != minterController) {
            revert NotMinterOrController();
        }
        if (amount == 0) revert InvalidMintAmount();
        if (
            p.derivativeContract != address(0) &&
            p.derivativeContract != actualDerivativeContract
        ) {
            revert DerivativeContractMismatch(p.derivativeContract, actualDerivativeContract);
        }
        if (p.seriesHash != bytes32(0) && p.seriesHash != actualSeriesHash) {
            revert SeriesMismatch(p.seriesHash, actualSeriesHash);
        }

        uint64 nowTs = uint64(block.timestamp);
        if (p.validAfter != 0 && nowTs < p.validAfter) {
            revert PermitNotActiveYet(nowTs, p.validAfter);
        }
        if (nowTs >= p.expiresAt) {
            revert PermitExpiredError(nowTs, p.expiresAt);
        }

        uint256 remaining = p.maxMintAmount - p.mintedAmount;
        if (amount > remaining) {
            revert MintCapExceeded(amount, remaining);
        }

        p.mintedAmount += amount;
        remainingMintAmount = p.maxMintAmount - p.mintedAmount;

        emit DerivativeMintRecorded(
            permitId,
            msg.sender,
            actualDerivativeContract,
            actualSeriesHash,
            amount,
            remainingMintAmount
        );
    }

    /**
     * @notice Revokes a derivative mint permit immediately.
     */
    function revokePermit(bytes32 permitId) external {
        DerivativeMintPermit storage p = _permits[permitId];
        if (p.issuer == address(0)) revert PermitNotFound(permitId);
        if (msg.sender != p.issuer && msg.sender != minterController) {
            revert NotIssuerOrController();
        }
        if (!p.revoked) {
            p.revoked = true;
            emit DerivativeMintPermitRevoked(permitId, msg.sender, uint64(block.timestamp));
        }
    }

    /**
     * @notice Checks whether a derivative mint permit is currently valid for `amount`.
     */
    function isPermitValid(
        bytes32 permitId,
        address actualDerivativeContract,
        bytes32 actualSeriesHash,
        uint256 amount
    ) external view returns (bool valid, string memory reason) {
        DerivativeMintPermit storage p = _permits[permitId];
        if (p.issuer == address(0)) return (false, "NOT_FOUND");
        if (p.revoked) return (false, "REVOKED");
        if (amount == 0) return (false, "ZERO_AMOUNT");
        if (
            p.derivativeContract != address(0) &&
            p.derivativeContract != actualDerivativeContract
        ) {
            return (false, "CONTRACT_MISMATCH");
        }
        if (p.seriesHash != bytes32(0) && p.seriesHash != actualSeriesHash) {
            return (false, "SERIES_MISMATCH");
        }

        uint64 nowTs = uint64(block.timestamp);
        if (p.validAfter != 0 && nowTs < p.validAfter) return (false, "NOT_YET_ACTIVE");
        if (nowTs >= p.expiresAt) return (false, "EXPIRED");
        if (amount > p.maxMintAmount - p.mintedAmount) return (false, "MINT_CAP_EXCEEDED");

        return (true, "VALID");
    }

    /**
     * @notice Returns full derivative mint permit details for `permitId`.
     */
    function getPermit(bytes32 permitId) external view returns (DerivativeMintPermit memory) {
        DerivativeMintPermit memory p = _permits[permitId];
        if (p.issuer == address(0)) revert PermitNotFound(permitId);
        return p;
    }
}

