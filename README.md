# Crossbones

Proof-of-concept transaction-bundle-assisted OTC NFT trades. Purchase funds are escrowed by a smart contract, but the token transfer is performed by the seller as part of a bundle of transactions that also validate and withdraw the funds. 

A sale consists of four transactions made in two stages:

## Stage 1:
The buyer submits a deposit to pay for a specific token (address + ID) as well as a recipient address of the token. The deposit is held in escrow by the contract and may be withdrawn at any time.

To prevent front-running of withdrawals, the buyer must provide the seller with a signature of the following struct:

```solidity
struct Claim {
    address tokenAddress;
    uint256 tokenId;
    uint256 expiredTimestamp;
}
```

To somewhat mitigate signature phishing, the expiredTimestamp must be at most 30 minutes in the future.

## Stage 2:
The seller submits a bundle of transactions to a block builder on the condition that they all must succeed.

1. The seller calls `commitClaim` to commit to selling a specific token (address + ID) to a specific buyer for a specific amount.
   1. The seller is verified to be the owner of the token. The seller, the buyer, and the amount are stored along with the current block number. 
2. The seller transfers the token to the specified recipient according to the buyer's deposit.
3. The seller calls `claimDeposit` with the Claim struct, buyer address, and buyer-provided signature.
   1. The signature and commitments are validated, ownership of the token is verified to be the buyer-specified recipient, and the deposit entry is cleared with the amount forwarded to the seller specified in the commitment.

## Caveats:
- The seller must be able to submit a bundle of transactions to a block builder on the condition that they all must succeed.
- The network must process all transactions as part of the same block. On some networks, each transaction is its own block.