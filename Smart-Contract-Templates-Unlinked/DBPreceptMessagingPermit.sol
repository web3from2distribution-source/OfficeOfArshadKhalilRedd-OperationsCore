[Smart-Contract Address: 0xD7ACd2a9FD159E69Bb102A1ca21C9a3e3A5F771B ]

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DBPreceptMessagingPermit
 * @notice Standalone direct on-chain messaging permit template.
 * @dev Written as a self-contained template with direct on-chain issuance and
 *      no external contract dependencies or automated off-chain hooks.
 */
contract DBPreceptMessagingPermit {
    struct MessagingPermit {
        address sender;        // Principal / issuer authorizing outbound messages
        address operator;      // Permitted operator/relayer/agent address (or sender)
        address recipient;     // Target recipient address (address(0) if unrestricted)
        bytes32 channelHash;   // Topic, route, or message-type identifier hash
        uint32 maxMessages;    // Maximum number of messages permitted under this permit
        uint32 messagesUsed;   // Number of messages recorded so far
        uint64 validAfter;     // Earliest active timestamp (0 = active immediately)
        uint64 expiresAt;      // Expiration timestamp (must exceed block.timestamp & validAfter)
        uint256 nonce;         // Per-sender sequence nonce
        bool revoked;          // True if revoked prior to expiration
    }

    /// @notice Mapping from permitId => MessagingPermit record
    mapping(bytes32 => MessagingPermit) private _permits;

    /// @notice Current sequential nonce per sender address
    mapping(address => uint256) public nonces;

    /// @notice Optional administrative/clearing authority address
    address public authority;

    event AuthorityUpdated(address indexed previousAuthority, address indexed newAuthority);

    event MessagingPermitIssued(
        bytes32 indexed permitId,
        address indexed sender,
        address indexed operator,
        address recipient,
        bytes32 channelHash,
        uint32 maxMessages,
        uint64 validAfter,
        uint64 expiresAt,
        uint256 nonce
    );

    event MessagePermitRecorded(
        bytes32 indexed permitId,
        address indexed caller,
        address indexed recipient,
        bytes32 channelHash,
        uint32 messagesUsed,
        uint32 remainingMessages
    );

    event MessagingPermitRevoked(
        bytes32 indexed permitId,
        address indexed revokedBy,
        uint64 revokedAt
    );

    error ZeroAddress();
    error InvalidMessageQuota();
    error InvalidWindow(uint64 validAfter, uint64 expiresAt);
    error PermitAlreadyExists(bytes32 permitId);
    error PermitNotFound(bytes32 permitId);
    error NotSenderOrAuthority();
    error NotOperatorOrAuthority();
    error PermitRevokedError();
    error PermitNotActiveYet(uint64 currentTime, uint64 validAfter);
    error PermitExpiredError(uint64 currentTime, uint64 expiresAt);
    error RecipientMismatch(address expectedRecipient, address actualRecipient);
    error ChannelMismatch(bytes32 expectedChannel, bytes32 actualChannel);
    error MessageQuotaExceeded(uint32 requested, uint32 remaining);

    constructor(address initialAuthority) {
        authority = initialAuthority;
        emit AuthorityUpdated(address(0), initialAuthority);
    }

    /**
     * @notice Updates the authority address (callable by current authority if set).
     */
    function setAuthority(address newAuthority) external {
        if (authority != address(0) && msg.sender != authority) {
            revert NotSenderOrAuthority();
        }
        if (newAuthority == address(0)) revert ZeroAddress();
        address prev = authority;
        authority = newAuthority;
        emit AuthorityUpdated(prev, newAuthority);
    }

    /**
     * @notice Computes a deterministic permit ID for a messaging permit.
     */
    function computePermitId(
        address sender,
        address operator,
        address recipient,
        bytes32 channelHash,
        uint32 maxMessages,
        uint64 validAfter,
        uint64 expiresAt,
        uint256 nonce
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                sender,
                operator,
                recipient,
                channelHash,
                maxMessages,
                validAfter,
                expiresAt,
                nonce
            )
        );
    }

    /**
     * @notice Issues a new direct on-chain messaging permit from `msg.sender`.
     */
    function issueMessagingPermit(
        address operator,
        address recipient,
        bytes32 channelHash,
        uint32 maxMessages,
        uint64 validAfter,
        uint64 expiresAt
    ) external returns (bytes32 permitId) {
        address sender = msg.sender;
        if (operator == address(0)) revert ZeroAddress();
        if (maxMessages == 0) revert InvalidMessageQuota();
        if (expiresAt <= block.timestamp || expiresAt <= validAfter) {
            revert InvalidWindow(validAfter, expiresAt);
        }

        uint256 currentNonce = nonces[sender];
        nonces[sender] = currentNonce + 1;

        permitId = computePermitId(
            sender,
            operator,
            recipient,
            channelHash,
            maxMessages,
            validAfter,
            expiresAt,
            currentNonce
        );

        if (_permits[permitId].sender != address(0)) {
            revert PermitAlreadyExists(permitId);
        }

        _permits[permitId] = MessagingPermit({
            sender: sender,
            operator: operator,
            recipient: recipient,
            channelHash: channelHash,
            maxMessages: maxMessages,
            messagesUsed: 0,
            validAfter: validAfter,
            expiresAt: expiresAt,
            nonce: currentNonce,
            revoked: false
        });

        emit MessagingPermitIssued(
            permitId,
            sender,
            operator,
            recipient,
            channelHash,
            maxMessages,
            validAfter,
            expiresAt,
            currentNonce
        );
    }

    /**
     * @notice Records message quota usage (`count`) against an active permit.
     */
    function consumeMessageQuota(
        bytes32 permitId,
        address actualRecipient,
        bytes32 actualChannelHash,
        uint32 count
    ) external returns (uint32 remainingMessages) {
        MessagingPermit storage p = _permits[permitId];
        if (p.sender == address(0)) revert PermitNotFound(permitId);
        if (p.revoked) revert PermitRevokedError();
        if (msg.sender != p.operator && msg.sender != authority) {
            revert NotOperatorOrAuthority();
        }
        if (count == 0) revert InvalidMessageQuota();
        if (actualRecipient == address(0)) revert ZeroAddress();
        if (p.recipient != address(0) && p.recipient != actualRecipient) {
            revert RecipientMismatch(p.recipient, actualRecipient);
        }
        if (p.channelHash != bytes32(0) && p.channelHash != actualChannelHash) {
            revert ChannelMismatch(p.channelHash, actualChannelHash);
        }

        uint64 nowTs = uint64(block.timestamp);
        if (p.validAfter != 0 && nowTs < p.validAfter) {
            revert PermitNotActiveYet(nowTs, p.validAfter);
        }
        if (nowTs >= p.expiresAt) {
            revert PermitExpiredError(nowTs, p.expiresAt);
        }

        uint32 remaining = p.maxMessages - p.messagesUsed;
        if (count > remaining) {
            revert MessageQuotaExceeded(count, remaining);
        }

        p.messagesUsed += count;
        remainingMessages = p.maxMessages - p.messagesUsed;

        emit MessagePermitRecorded(
            permitId,
            msg.sender,
            actualRecipient,
            actualChannelHash,
            p.messagesUsed,
            remainingMessages
        );
    }

    /**
     * @notice Revokes a messaging permit immediately.
     */
    function revokePermit(bytes32 permitId) external {
        MessagingPermit storage p = _permits[permitId];
        if (p.sender == address(0)) revert PermitNotFound(permitId);
        if (msg.sender != p.sender && msg.sender != authority) {
            revert NotSenderOrAuthority();
        }
        if (!p.revoked) {
            p.revoked = true;
            emit MessagingPermitRevoked(permitId, msg.sender, uint64(block.timestamp));
        }
    }

    /**
     * @notice Checks whether a messaging permit is currently valid for `count` messages.
     */
    function isPermitValid(
        bytes32 permitId,
        address actualRecipient,
        bytes32 actualChannelHash,
        uint32 count
    ) external view returns (bool valid, string memory reason) {
        MessagingPermit storage p = _permits[permitId];
        if (p.sender == address(0)) return (false, "NOT_FOUND");
        if (p.revoked) return (false, "REVOKED");
        if (count == 0) return (false, "ZERO_COUNT");
        if (actualRecipient == address(0)) return (false, "ZERO_RECIPIENT");
        if (p.recipient != address(0) && p.recipient != actualRecipient) {
            return (false, "RECIPIENT_MISMATCH");
        }
        if (p.channelHash != bytes32(0) && p.channelHash != actualChannelHash) {
            return (false, "CHANNEL_MISMATCH");
        }

        uint64 nowTs = uint64(block.timestamp);
        if (p.validAfter != 0 && nowTs < p.validAfter) return (false, "NOT_YET_ACTIVE");
        if (nowTs >= p.expiresAt) return (false, "EXPIRED");
        if (count > p.maxMessages - p.messagesUsed) return (false, "QUOTA_EXCEEDED");

        return (true, "VALID");
    }

    /**
     * @notice Returns full messaging permit record for `permitId`.
     */
    function getPermit(bytes32 permitId) external view returns (MessagingPermit memory) {
        MessagingPermit memory p = _permits[permitId];
        if (p.sender == address(0)) revert PermitNotFound(permitId);
        return p;
    }
}



