[Contract-Address: 0x5E809A58Da0f16d7A89BaEEA197f7d0A5Fe0d521]

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISubValidator {
    function verifyLocalAccess(address member) external view returns (bool);
}

/**
 * @title SubElector
 * @notice Localized community governance contract tied to a creator's unique SubValidator instance.
 */
contract SubElector {
    ISubValidator public immutable subValidator;

    struct LocalProposal {
        string title;
        uint256 approvals;
        bool open;
    }

    mapping(uint256 => LocalProposal) public localProposals;
    mapping(uint256 => mapping(address => bool)) public localHasVoted;
    uint256 public localProposalCount;

    event LocalProposalCreated(uint256 indexed proposalId, string title);
    event LocalVoted(uint256 indexed proposalId, address indexed voter);

    constructor(address _subValidator) {
        subValidator = ISubValidator(_subValidator);
    }

    function createLocalProposal(string memory title) external {
        require(subValidator.verifyLocalAccess(msg.sender), "Unauthorized: Inactive local access or master subscription");

        localProposals[localProposalCount] = LocalProposal({
            title: title,
            approvals: 0,
            open: true
        });

        emit LocalProposalCreated(localProposalCount, title);
        localProposalCount++;
    }

    function voteLocal(uint256 proposalId) external {
        require(subValidator.verifyLocalAccess(msg.sender), "Unauthorized: Inactive local access or master subscription");
        require(localProposals[proposalId].open, "Local proposal is closed");
        require(!localHasVoted[proposalId][msg.sender], "Already voted on this local proposal");

        localHasVoted[proposalId][msg.sender] = true;
        localProposals[proposalId].approvals++;

        emit LocalVoted(proposalId, msg.sender);
    }
}
