// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

struct Claim {
    address tokenAddress;
    uint256 tokenId;
    uint256 expiredTimestamp;
}

struct Deposit {
    address tokenRecipient;
    uint96 paymentBalance;
}

struct ClaimCommitment {
    address seller;
    uint96 blockNumber;
    address buyer;
    uint96 depositAmount;
}
