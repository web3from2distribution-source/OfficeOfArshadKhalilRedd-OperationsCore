[Contract-Address: 0xfbc9Dea173a8871C6F0B91f05b845553678B42c0]

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMasterValidator {
    function isValidated(address user) external view returns (bool);
}

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract MasterMusicCatalog {
    IMasterValidator public immutable masterValidator;
    IERC20 public immutable jpausToken = IERC20(0x24F7f09530401B461772b0008f3098C8F4972C89);
    address public owner;

    uint256 public uploadFee;

    struct Track {
        address artist;
        string ipfsUri;
        uint256 price;
        bool active;
    }

    mapping(uint256 => Track) public catalog;
    mapping(address => mapping(uint256 => bool)) public userLibrary;
    uint256 public trackCount;

    event TrackPublished(uint256 indexed trackId, address indexed artist, string ipfsUri, uint256 price);
    event TrackPurchased(uint256 indexed trackId, address indexed buyer, uint256 price);
    event UploadFeeUpdated(uint256 newUploadFee);

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    modifier onlyValidated() {
        require(masterValidator.isValidated(msg.sender), "Caller not validated by MasterValidator");
        _;
    }

    constructor(address _validator, uint256 _uploadFee) {
        owner = msg.sender;
        masterValidator = IMasterValidator(_validator);
        uploadFee = _uploadFee;
    }

    function publishTrack(string calldata ipfsUri, uint256 price) external onlyValidated {
        require(jpausToken.transferFrom(msg.sender, address(this), uploadFee), "JPAUS upload fee transfer failed");

        trackCount++;
        catalog[trackCount] = Track({
            artist: msg.sender,
            ipfsUri: ipfsUri,
            price: price,
            active: true
        });

        emit TrackPublished(trackCount, msg.sender, ipfsUri, price);
    }

    function purchaseTrack(uint256 trackId) external onlyValidated {
        Track memory track = catalog[trackId];
        require(track.active, "Track not active");
        require(!userLibrary[msg.sender][trackId], "Already owned");

        require(jpausToken.transferFrom(msg.sender, track.artist, track.price), "JPAUS track purchase transfer failed");

        userLibrary[msg.sender][trackId] = true;
        emit TrackPurchased(trackId, msg.sender, track.price);
    }

    function checkAccess(address user, uint256 trackId) external view returns (bool) {
        return masterValidator.isValidated(user) && userLibrary[user][trackId];
    }

    function updateUploadFee(uint256 _newUploadFee) external onlyOwner {
        uploadFee = _newUploadFee;
        emit UploadFeeUpdated(_newUploadFee);
    }

    function withdrawTokens(uint256 amount) external onlyOwner {
        require(jpausToken.transfer(owner, amount), "Token withdrawal failed");
    }
}
