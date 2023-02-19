// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC721 } from "openzeppelin-contracts/token/ERC721/ERC721.sol";

contract TestERC721 is ERC721("test", "test") {
    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }
}
