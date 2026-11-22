[Smart-Contract Address: 0x7EF2e0048f5bAeDe046f6BF797943daF4ED8CB47 ]

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DBPreceptSessionExpirePermit
 * @notice Standalone direct on-chain session-expiration permit template.
 * @dev Written as a self-contained template with direct on-chain issuance and
 *      no external contract dependencies or automated off-chain hooks.
 */
contract DBPreceptSessionExpirePermit {
    struct SessionPermit {
        address principal;     // Principal / owner opening the session permit
        address sessionAgent;  // Bound AI agent or session operator address
        bytes32 sessionTag;    // Session context, workflow, or policy identifier hash
        uint32 maxActions;     // Maximum allowed actions/steps during the session
        uint32 actionsUsed;    // Number of actions recorded in this session
        uint64 startedAt;      // Timestamp when the session permit was created
        uint64 expiresAt;      // Hard session expiration timestamp
        uint64 maxIdleSeconds; // Optional max seconds between heartbeats/actions (0 = disabled)
        uint64 lastActiveAt;   // Timestamp of last recorded action or heartbeat touch
        uint256 nonce;         // Per-principal sequence nonce
        bool revoked;          // True if explicitly revoked before expiration
    }

    /// @notice Mapping from sessionId => SessionPermit record
    mapping(bytes32 => SessionPermit) private _sessions;

    /// @notice Current sequential nonce per principal address
    mapping(address => uint256) public nonces;

    /// @notice Optional administrative/clearing supervisor address
    address public supervisor;

    event SupervisorUpdated(address indexed previousSupervisor, address indexed newSupervisor);

    event SessionPermitOpened(
        bytes32 indexed sessionId,
        address indexed principal,
        address indexed sessionAgent,
        bytes32 sessionTag,
        uint32 maxActions,
        uint64 startedAt,
        uint64 expiresAt,
        uint64 maxIdleSeconds,
        uint256 nonce
    );

    event SessionActionRecorded(
        bytes32 indexed sessionId,
        address indexed caller,
        uint32 actionsUsed,
        uint32 remainingActions,
        uint64 activeAt
    );

    event SessionHeartbeatTouched(
        bytes32 indexed sessionId,
        address indexed caller,
        uint64 touchedAt
    );

    event SessionPermitRevoked(
        bytes32 indexed sessionId,
        address indexed revokedBy,
        uint64 revokedAt
    );

    error ZeroAddress();
    error InvalidActionLimit();
    error InvalidDuration(uint64 currentTime, uint64 expiresAt);
    error SessionAlreadyExists(bytes32 sessionId);
    error SessionNotFound(bytes32 sessionId);
    error NotPrincipalOrSupervisor();
    error NotSessionAgentOrSupervisor();
    error SessionRevokedError();
    error SessionExpiredError(uint64 currentTime, uint64 expiresAt);
    error SessionIdleTimedOut(uint64 lastActiveAt, uint64 maxIdleSeconds, uint64 currentTime);
    error ActionLimitExceeded(uint32 requested, uint32 remaining);

    constructor(address initialSupervisor) {
        supervisor = initialSupervisor;
        emit SupervisorUpdated(address(0), initialSupervisor);
    }

    /**
     * @notice Updates the supervisor address (callable by current supervisor if set).
     */
    function setSupervisor(address newSupervisor) external {
        if (supervisor != address(0) && msg.sender != supervisor) {
            revert NotPrincipalOrSupervisor();
        }
        if (newSupervisor == address(0)) revert ZeroAddress();
        address prev = supervisor;
        supervisor = newSupervisor;
        emit SupervisorUpdated(prev, newSupervisor);
    }

    /**
     * @notice Computes a deterministic session permit identifier.
     */
    function computeSessionId(
        address principal,
        address sessionAgent,
        bytes32 sessionTag,
        uint32 maxActions,
        uint64 expiresAt,
        uint64 maxIdleSeconds,
        uint256 nonce
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                principal,
                sessionAgent,
                sessionTag,
                maxActions,
                expiresAt,
                maxIdleSeconds,
                nonce
            )
        );
    }

    /**
     * @notice Opens a new direct on-chain session permit from `msg.sender` as `principal`.
     */
    function openSessionPermit(
        address sessionAgent,
        bytes32 sessionTag,
        uint32 maxActions,
        uint64 expiresAt,
        uint64 maxIdleSeconds
    ) external returns (bytes32 sessionId) {
        address principal = msg.sender;
        if (sessionAgent == address(0)) revert ZeroAddress();
        if (maxActions == 0) revert InvalidActionLimit();

        uint64 nowTs = uint64(block.timestamp);
        if (expiresAt <= nowTs) {
            revert InvalidDuration(nowTs, expiresAt);
        }

        uint256 currentNonce = nonces[principal];
        nonces[principal] = currentNonce + 1;

        sessionId = computeSessionId(
            principal,
            sessionAgent,
            sessionTag,
            maxActions,
            expiresAt,
            maxIdleSeconds,
            currentNonce
        );

        if (_sessions[sessionId].principal != address(0)) {
            revert SessionAlreadyExists(sessionId);
        }

        _sessions[sessionId] = SessionPermit({
            principal: principal,
            sessionAgent: sessionAgent,
            sessionTag: sessionTag,
            maxActions: maxActions,
            actionsUsed: 0,
            startedAt: nowTs,
            expiresAt: expiresAt,
            maxIdleSeconds: maxIdleSeconds,
            lastActiveAt: nowTs,
            nonce: currentNonce,
            revoked: false
        });

        emit SessionPermitOpened(
            sessionId,
            principal,
            sessionAgent,
            sessionTag,
            maxActions,
            nowTs,
            expiresAt,
            maxIdleSeconds,
            currentNonce
        );
    }

    /**
     * @notice Records `actionCount` actions against a non-expired, non-revoked session.
     */
    function recordSessionAction(
        bytes32 sessionId,
        uint32 actionCount
    ) external returns (uint32 remainingActions) {
        SessionPermit storage s = _sessions[sessionId];
        if (s.principal == address(0)) revert SessionNotFound(sessionId);
        if (s.revoked) revert SessionRevokedError();
        if (msg.sender != s.sessionAgent && msg.sender != supervisor) {
            revert NotSessionAgentOrSupervisor();
        }
        if (actionCount == 0) revert InvalidActionLimit();

        uint64 nowTs = uint64(block.timestamp);
        if (nowTs >= s.expiresAt) {
            revert SessionExpiredError(nowTs, s.expiresAt);
        }
        if (s.maxIdleSeconds != 0 && nowTs > s.lastActiveAt + s.maxIdleSeconds) {
            revert SessionIdleTimedOut(s.lastActiveAt, s.maxIdleSeconds, nowTs);
        }

        uint32 remaining = s.maxActions - s.actionsUsed;
        if (actionCount > remaining) {
            revert ActionLimitExceeded(actionCount, remaining);
        }

        s.actionsUsed += actionCount;
        s.lastActiveAt = nowTs;
        remainingActions = s.maxActions - s.actionsUsed;

        emit SessionActionRecorded(sessionId, msg.sender, s.actionsUsed, remainingActions, nowTs);
    }

    /**
     * @notice Updates `lastActiveAt` to keep an active session alive within its `maxIdleSeconds` window.
     */
    function touchSession(bytes32 sessionId) external {
        SessionPermit storage s = _sessions[sessionId];
        if (s.principal == address(0)) revert SessionNotFound(sessionId);
        if (s.revoked) revert SessionRevokedError();
        if (msg.sender != s.sessionAgent && msg.sender != supervisor) {
            revert NotSessionAgentOrSupervisor();
        }

        uint64 nowTs = uint64(block.timestamp);
        if (nowTs >= s.expiresAt) {
            revert SessionExpiredError(nowTs, s.expiresAt);
        }
        if (s.maxIdleSeconds != 0 && nowTs > s.lastActiveAt + s.maxIdleSeconds) {
            revert SessionIdleTimedOut(s.lastActiveAt, s.maxIdleSeconds, nowTs);
        }

        s.lastActiveAt = nowTs;
        emit SessionHeartbeatTouched(sessionId, msg.sender, nowTs);
    }

    /**
     * @notice Revokes a session permit immediately prior to expiration.
     */
    function revokeSession(bytes32 sessionId) external {
        SessionPermit storage s = _sessions[sessionId];
        if (s.principal == address(0)) revert SessionNotFound(sessionId);
        if (msg.sender != s.principal && msg.sender != supervisor) {
            revert NotPrincipalOrSupervisor();
        }
        if (!s.revoked) {
            s.revoked = true;
            emit SessionPermitRevoked(sessionId, msg.sender, uint64(block.timestamp));
        }
    }

    /**
     * @notice Checks whether a session permit is currently valid for `actionCount` actions.
     */
    function isSessionValid(
        bytes32 sessionId,
        uint32 actionCount
    ) external view returns (bool valid, string memory reason) {
        SessionPermit storage s = _sessions[sessionId];
        if (s.principal == address(0)) return (false, "NOT_FOUND");
        if (s.revoked) return (false, "REVOKED");
        if (actionCount == 0) return (false, "ZERO_ACTIONS");

        uint64 nowTs = uint64(block.timestamp);
        if (nowTs >= s.expiresAt) return (false, "EXPIRED");
        if (s.maxIdleSeconds != 0 && nowTs > s.lastActiveAt + s.maxIdleSeconds) {
            return (false, "IDLE_TIMEOUT");
        }
        if (actionCount > s.maxActions - s.actionsUsed) {
            return (false, "ACTION_LIMIT_EXCEEDED");
        }

        return (true, "VALID");
    }

    /**
     * @notice Returns full session permit details for `sessionId`.
     */
    function getSession(bytes32 sessionId) external view returns (SessionPermit memory) {
        SessionPermit memory s = _sessions[sessionId];
        if (s.principal == address(0)) revert SessionNotFound(sessionId);
        return s;
    }
}

