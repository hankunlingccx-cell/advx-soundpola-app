// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SoundPolaNFT is ERC721, ERC721URIStorage, Ownable {
    uint256 private _nextTokenId;
    mapping(address => bool) public minters;

    modifier onlyMinter() {
        require(owner() == msg.sender || minters[msg.sender], "not minter");
        _;
    }

    constructor() ERC721("SoundPola", "SPOLA") Ownable(msg.sender) {
        minters[msg.sender] = true;
    }

    function setMinter(address account, bool authorized) public onlyOwner {
        minters[account] = authorized;
    }

    function safeMint(address to, string memory uri) public onlyMinter {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    function safeMintBatch(address to, string[] memory uris) public onlyMinter {
        for (uint256 i = 0; i < uris.length; i++) {
            safeMint(to, uris[i]);
        }
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
