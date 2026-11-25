[Contract Address: 0x956A66691CE062c17f6B7698E10519013034F0D7]

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMasterValidator {
    function verifySubscription(address user) external view returns (bool);
}

/**
 * @title MasterElector
 * @notice Global root election contract governed exclusively by the Master Validator.
 */
contract MasterElector {
    address public constant MASTER_VALIDATOR = 0x4d6B5cf0f3B289461A75C3d27aC32B2555A896D4;

    struct Proposal {
        string description;
        uint256 voteCount;
        bool active;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    uint256 public proposalCount;

    event ProposalCreated(uint256 indexed proposalId, string description);
    event Voted(uint256 indexed proposalId, address indexed voter);

    function createProposal(string memory description) external {
        require(IMasterValidator(MASTER_VALIDATOR).verifySubscription(msg.sender), "Master subscription required");
        
        proposals[proposalCount] = Proposal({
            description: description,
            voteCount: 0,
            active: true
        });

        emit ProposalCreated(proposalCount, description);
        proposalCount++;
    }

    function vote(uint256 proposalId) external {
        require(IMasterValidator(MASTER_VALIDATOR).verifySubscription(msg.sender), "Master subscription required");
        require(proposals[proposalId].active, "Proposal is not active");
        require(!hasVoted[proposalId][msg.sender], "Already voted on this proposal");

        hasVoted[proposalId][msg.sender] = true;
        proposals[proposalId].voteCount++;

        emit Voted(proposalId, msg.sender);
    }
}
