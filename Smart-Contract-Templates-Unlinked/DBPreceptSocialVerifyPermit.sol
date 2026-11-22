[Smart-Contract Address: 0xDA0bab807633f07f013f94DD0E6A4F96F8742B53 ]

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DBPreceptSocialVerifyPermit
 * @notice Standalone direct on-chain social-verification permit template.
 * @dev Written as a self-contained template with direct on-chain issuance and
 *      no external contract dependencies or automated off-chain hooks.
 */
contract DBPreceptSocialVerifyPermit {
    struct SocialVerifyPermit {
        address issuer;             // Principal / authority issuing the verification permit
        address verifier;           // Permitted verifier / operator / AI agent address
        address subject;            // Target wallet/account being verified (address(0) if open)
        bytes32 claimHash;          // Hash of social platform, handle, or verification claim
        uint32 maxVerifications;    // Maximum verifications allowed under this permit
        uint32 verificationsUsed;   // Number of verifications recorded so far
        uint64 validAfter;          // Earliest active timestamp (0 = active immediately)
        uint64 expiresAt;           // Expiration timestamp (must exceed block.timestamp & validAfter)
        uint256 nonce;              // Per-issuer sequence nonce
        bool revoked;               // True if revoked prior to expiration
    }

    /// @notice Mapping from permitId => SocialVerifyPermit record
    mapping(bytes32 => SocialVerifyPermit) private _permits;

    /// @notice Current sequential nonce per issuer address
    mapping(address => uint256) public nonces;

    /// @notice Optional administrative/clearing registrar address
    address public registrar;

    event RegistrarUpdated(address indexed previousRegistrar, address indexed newRegistrar);

    event SocialVerifyPermitIssued(
        bytes32 indexed permitId,
        address indexed issuer,
        address indexed verifier,
        address subject,
        bytes32 claimHash,
        uint32 maxVerifications,
        uint64 validAfter,
        uint64 expiresAt,
        uint256 nonce
    );

    event SocialVerificationRecorded(
        bytes32 indexed permitId,
        address indexed caller,
        address indexed subject,
        bytes32 claimHash,
        uint32 verificationsUsed,
        uint32 remainingVerifications
    );

    event SocialVerifyPermitRevoked(
        bytes32 indexed permitId,
        address indexed revokedBy,
        uint64 revokedAt
    );

    error ZeroAddress();
    error InvalidVerificationQuota();
    error InvalidWindow(uint64 validAfter, uint64 expiresAt);
    error PermitAlreadyExists(bytes32 permitId);
    error PermitNotFound(bytes32 permitId);
    error NotIssuerOrRegistrar();
    error NotVerifierOrRegistrar();
    error PermitRevokedError();
    error PermitNotActiveYet(uint64 currentTime, uint64 validAfter);
    error PermitExpiredError(uint64 currentTime, uint64 expiresAt);
    error SubjectMismatch(address expectedSubject, address actualSubject);
    error ClaimMismatch(bytes32 expectedClaim, bytes32 actualClaim);
    error VerificationQuotaExceeded(uint32 requested, uint32 remaining);

    constructor(address initialRegistrar) {
        registrar = initialRegistrar;
        emit RegistrarUpdated(address(0), initialRegistrar);
    }

    /**
     * @notice Updates the registrar address (callable by current registrar if set).
     */
    function setRegistrar(address newRegistrar) external {
        if (registrar != address(0) && msg.sender != registrar) {
            revert NotIssuerOrRegistrar();
        }
        if (newRegistrar == address(0)) revert ZeroAddress();
        address prev = registrar;
        registrar = newRegistrar;
        emit RegistrarUpdated(prev, newRegistrar);
    }

    /**
     * @notice Computes a deterministic permit ID for a social verification permit.
     */
    function computePermitId(
        address issuer,
        address verifier,
        address subject,
        bytes32 claimHash,
        uint32 maxVerifications,
        uint64 validAfter,
        uint64 expiresAt,
        uint256 nonce
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                issuer,
                verifier,
                subject,
                claimHash,
                maxVerifications,
                validAfter,
                expiresAt,
                nonce
            )
        );
    }

    /**
     * @notice Issues a new direct on-chain social verification permit from `msg.sender`.
     */
    function issueSocialVerifyPermit(
        address verifier,
        address subject,
        bytes32 claimHash,
        uint32 maxVerifications,
        uint64 validAfter,
        uint64 expiresAt
    ) external returns (bytes32 permitId) {
        address issuer = msg.sender;
        if (verifier == address(0)) revert ZeroAddress();
        if (maxVerifications == 0) revert InvalidVerificationQuota();
        if (expiresAt <= block.timestamp || expiresAt <= validAfter) {
            revert InvalidWindow(validAfter, expiresAt);
        }

        uint256 currentNonce = nonces[issuer];
        nonces[issuer] = currentNonce + 1;

        permitId = computePermitId(
            issuer,
            verifier,
            subject,
            claimHash,
            maxVerifications,
            validAfter,
            expiresAt,
            currentNonce
        );

        if (_permits[permitId].issuer != address(0)) {
            revert PermitAlreadyExists(permitId);
        }

        _permits[permitId] = SocialVerifyPermit({
            issuer: issuer,
            verifier: verifier,
            subject: subject,
            claimHash: claimHash,
            maxVerifications: maxVerifications,
            verificationsUsed: 0,
            validAfter: validAfter,
            expiresAt: expiresAt,
            nonce: currentNonce,
            revoked: false
        });

        emit SocialVerifyPermitIssued(
            permitId,
            issuer,
            verifier,
            subject,
            claimHash,
            maxVerifications,
            validAfter,
            expiresAt,
            currentNonce
        );
    }

    /**
     * @notice Records `count` verification usages against an active permit.
     */
    function recordVerification(
        bytes32 permitId,
        address actualSubject,
        bytes32 actualClaimHash,
        uint32 count
    ) external returns (uint32 remainingVerifications) {
        SocialVerifyPermit storage p = _permits[permitId];
        if (p.issuer == address(0)) revert PermitNotFound(permitId);
        if (p.revoked) revert PermitRevokedError();
        if (msg.sender != p.verifier && msg.sender != registrar) {
            revert NotVerifierOrRegistrar();
        }
        if (count == 0) revert InvalidVerificationQuota();
        if (actualSubject == address(0)) revert ZeroAddress();
        if (p.subject != address(0) && p.subject != actualSubject) {
            revert SubjectMismatch(p.subject, actualSubject);
        }
        if (p.claimHash != bytes32(0) && p.claimHash != actualClaimHash) {
            revert ClaimMismatch(p.claimHash, actualClaimHash);
        }

        uint64 nowTs = uint64(block.timestamp);
        if (p.validAfter != 0 && nowTs < p.validAfter) {
            revert PermitNotActiveYet(nowTs, p.validAfter);
        }
        if (nowTs >= p.expiresAt) {
            revert PermitExpiredError(nowTs, p.expiresAt);
        }

        uint32 remaining = p.maxVerifications - p.verificationsUsed;
        if (count > remaining) {
            revert VerificationQuotaExceeded(count, remaining);
        }

        p.verificationsUsed += count;
        remainingVerifications = p.maxVerifications - p.verificationsUsed;

        emit SocialVerificationRecorded(
            permitId,
            msg.sender,
            actualSubject,
            actualClaimHash,
            p.verificationsUsed,
            remainingVerifications
        );
    }

    /**
     * @notice Revokes a social verification permit immediately.
     */
    function revokePermit(bytes32 permitId) external {
        SocialVerifyPermit storage p = _permits[permitId];
        if (p.issuer == address(0)) revert PermitNotFound(permitId);
        if (msg.sender != p.issuer && msg.sender != registrar) {
            revert NotIssuerOrRegistrar();
        }
        if (!p.revoked) {
            p.revoked = true;
            emit SocialVerifyPermitRevoked(permitId, msg.sender, uint64(block.timestamp));
        }
    }

    /**
     * @notice Checks whether a social verification permit is currently valid for `count` verifications.
     */
    function isPermitValid(
        bytes32 permitId,
        address actualSubject,
        bytes32 actualClaimHash,
        uint32 count
    ) external view returns (bool valid, string memory reason) {
        SocialVerifyPermit storage p = _permits[permitId];
        if (p.issuer == address(0)) return (false, "NOT_FOUND");
        if (p.revoked) return (false, "REVOKED");
        if (count == 0) return (false, "ZERO_COUNT");
        if (actualSubject == address(0)) return (false, "ZERO_SUBJECT");
        if (p.subject != address(0) && p.subject != actualSubject) {
            return (false, "SUBJECT_MISMATCH");
        }
        if (p.claimHash != bytes32(0) && p.claimHash != actualClaimHash) {
            return (false, "CLAIM_MISMATCH");
        }

        uint64 nowTs = uint64(block.timestamp);
        if (p.validAfter != 0 && nowTs < p.validAfter) return (false, "NOT_YET_ACTIVE");
        if (nowTs >= p.expiresAt) return (false, "EXPIRED");
        if (count > p.maxVerifications - p.verificationsUsed) {
            return (false, "QUOTA_EXCEEDED");
        }

        return (true, "VALID");
    }

    /**
     * @notice Returns full social verification permit details for `permitId`.
     */
    function getPermit(bytes32 permitId) external view returns (SocialVerifyPermit memory) {
        SocialVerifyPermit memory p = _permits[permitId];
        if (p.issuer == address(0)) revert PermitNotFound(permitId);
        return p;
    }
}

