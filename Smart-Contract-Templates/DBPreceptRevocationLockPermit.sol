[Smart-Contract Address: 0xd9145CCE52D386f254917e481eB44e9943F39138]

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Anything that wants to honor an owner's revocations asks this one question.
interface IRevocationLock {
    function isAllowed(address owner, address agent) external view returns (bool);
}

/// @title DBPreceptRevocationLockPermit
/// @notice A per-owner kill switch. Each address controls only its own entries, so there is
///         no admin key. Other contracts honor it by calling isAllowed(owner, agent).
///         Both switches can be turned back off by the owner.
contract DBPreceptRevocationLockPermit is IRevocationLock {
    mapping(address => mapping(address => bool)) public agentRevoked;
    mapping(address => bool) public frozen;

    event AgentRevokedSet(address indexed owner, address indexed agent, bool revoked);
    event FrozenSet(address indexed owner, bool isFrozen);

    function setAgentRevoked(address agent, bool revoked) external {
        agentRevoked[msg.sender][agent] = revoked;
        emit AgentRevokedSet(msg.sender, agent, revoked);
    }

    function setFrozen(bool isFrozen) external {
        frozen[msg.sender] = isFrozen;
        emit FrozenSet(msg.sender, isFrozen);
    }

    function isAllowed(address owner, address agent) external view returns (bool) {
        return !frozen[owner] && !agentRevoked[owner][agent];
    }
}
