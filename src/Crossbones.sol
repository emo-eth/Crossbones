// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC721 } from "openzeppelin-contracts/interfaces/IERC721.sol";
import { Claim, Deposit, ClaimCommitment } from "./lib/Structs.sol";

/**
 * @title  Crossbones
 * @author emo.eth
 * @notice Crossbones is a proof-of-concept payment escrow smart contract for
 *         OTC sales of NFTs, where marketplace smart contracts may not be able
 *         to facilitate the sale. It is designed to be used with a private
 * relayer
 *         that supports atomic bundles of transactions, ie, if any transaction
 *         in the bundle fails, all transactions in the bundle should be
 * reverted.
 *
 * A sale consists of four transactions made in two stages:
 *
 * Stage 1:
 *
 * The buyer submits a deposit to pay for a specific token (address + ID) as
 * well as a recipient address of the token. The deposit is held in escrow by
 * the contract and may be withdrawn at any time.
 *
 * To prevent front-running of deposit withdrawals, the buyer must provide the
 * seller with a signature of the following struct:
 *
 * struct Claim {
 *     address tokenAddress;
 *     uint256 tokenId;
 *     uint256 expiredTimestamp;
 * }
 *
 * To somewhat mitigate signature collection, the expiredTimestamp must be at
 * most 30 minutes in the future.
 *
 *
 * Stage 2:
 *
 * The seller submits an atomic bundle of transactions to a block builder on the
 * condition that they all must succeed.
 *
 * 1. The seller calls `commitClaim` to commit to selling a specific token
 *    (address + ID) to a specific buyer for a specific amount.
 *     - The seller is verified to be the owner of the token. The seller, the
 *       buyer, and the amount are stored along with the current block number.
 *
 * 2. The seller transfers the token to the specified recipient according to the
 *    buyer's deposit.
 *
 * 3. The seller calls `claimDeposit` with the Claim struct, buyer address, and
 *    buyer-provided signature.
 *     - The signature and commitments are validated, ownership of the token is
 *       verified to be the buyer-specified recipient, and the deposit entry is
 *       cleared with the amount forwarded to the seller specified in the
 *       commitment.
 *
 * Caveats:
 *
 * - The seller must be able to submit a bundle of transactions to a block
 * builder on the condition that they all must succeed.
 *
 * - The network must process all transactions as part of the same block. On
 *   some networks, each transaction is its own block.
 *
 */
contract Crossbones {
    error InvalidClaim();
    error InvalidDeposit();
    error DepositExists();
    error ActiveCommitment();
    error NotTokenOwner();
    error InvalidCommitment();
    error InvalidBuyer();
    error InvalidSignature();
    error ExpiredClaim();

    string public constant EIP712_DOMAIN_TYPE =
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
    bytes32 public constant EIP712_DOMAIN_TYPEHASH =
        keccak256(bytes(EIP712_DOMAIN_TYPE));
    string public constant EIP712_CLAIM_TYPE =
        "Claim(address tokenAddress,uint256 tokenId,uint256 expiredTimestamp)";
    bytes32 public constant EIP712_CLAIM_TYPEHASH =
        keccak256(bytes(EIP712_CLAIM_TYPE));

    bytes32 public immutable DOMAIN_SEPARATOR;
    string public constant NAME = "Crossbones";
    string public constant VERSION = "1";

    uint256 constant SIGNATURE_MAX_DURATION = 30 minutes;

    mapping(
        address user
            => mapping(
                address tokenAddress
                    => mapping(uint256 tokenId => Deposit deposit)
            )
    ) public deposits;

    mapping(
        address tokenAddress
            => mapping(uint256 tokenid => ClaimCommitment commitment)
    ) public commitments;

    mapping(bytes32 => bool) public usedSignatures;

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                abi.encode(NAME, VERSION, block.chainid, address(this))
            )
        );
    }

    /**
     * @notice A seller must commit to claiming a buy order for an NFT that they
     *         own within the same block it is claimed. This ensures that a buy
     *         claim cannot be front-run by the token receiver, if a builder
     *         were to allow insertion of transactions within the bundle
     *
     * @param tokenAddress nft smart contract of token being sold
     * @param tokenId nft token id to be sold and to verify that the caller owns
     * @param buyer address of the buyer who placed the buy order
     * @param depositAmount amount of native token deposited by the buyer
     */
    function commitClaim(
        address tokenAddress,
        uint256 tokenId,
        address buyer,
        uint256 depositAmount
    ) external {
        // note: would have to use some sort of timestamp-based commitment on
        // L2s that don't support multiple txs per block
        ClaimCommitment memory existingCommitment =
            commitments[tokenAddress][tokenId];

        // if the commitment exists and is from the same block, revert
        // since a malicious onERC721Received hook could try to update the claim
        // address
        if (uint256(existingCommitment.blockNumber) == block.number) {
            revert ActiveCommitment();
        }

        // validate that expected depositAmount is correct
        Deposit memory userDeposit = deposits[buyer][tokenAddress][tokenId];
        if (userDeposit.paymentBalance != depositAmount) {
            revert InvalidCommitment();
        }

        // validate that the caller owns the token, so a bundled claim cannot be
        // front-run, if the builder were to allow insertion of other
        // transactions within the bundle
        if (IERC721(tokenAddress).ownerOf(tokenId) != msg.sender) {
            revert NotTokenOwner();
        }
        ClaimCommitment memory commitment = ClaimCommitment({
            seller: msg.sender,
            blockNumber: uint96(block.number),
            buyer: buyer,
            depositAmount: uint96(depositAmount)
        });
        commitments[tokenAddress][tokenId] = commitment;
    }

    /**
     * @notice Deposit native token to place a buy order on an NFT
     * @param tokenAddress nft smart contract address to buy
     * @param tokenId nft token id to buy
     * @param recipient address to receive the NFT
     */
    function deposit(address tokenAddress, uint256 tokenId, address recipient)
        external
        payable
    {
        if (msg.value == 0) {
            revert InvalidDeposit();
        }
        Deposit storage _deposit = deposits[msg.sender][tokenAddress][tokenId];
        Deposit memory userDeposit = _deposit;
        if (userDeposit.paymentBalance > 0) {
            revert DepositExists();
        }

        userDeposit.tokenRecipient = recipient;
        userDeposit.paymentBalance += uint96(msg.value);
        deposits[msg.sender][tokenAddress][tokenId] = userDeposit;
    }

    /**
     * @notice Withdraw deposited native token from a buy order
     * @param tokenAddress nft smart contract buy order was placed on
     * @param tokenId specific token id buy order was placed on
     */
    function withdrawDeposit(address tokenAddress, uint256 tokenId) external {
        Deposit storage _deposit = deposits[msg.sender][tokenAddress][tokenId];
        Deposit memory userDeposit = _deposit;
        uint256 balance = userDeposit.paymentBalance;
        if (balance == 0) {
            revert InvalidDeposit();
        }
        delete deposits[msg.sender][tokenAddress][tokenId];
        (bool success, bytes memory reason) =
            msg.sender.call{ value: balance }("");
        if (!success) {
            assembly {
                revert(add(0x20, reason), mload(reason))
            }
        }
    }

    /**
     * @notice Claim a buy order by providing a claim, buyer, and signature.
     * Validates that the buyer and payment amounts are the same that the seller
     * commited to within the same block.
     * @param claim claim parameters to validate
     * @param buyer buyer address to validate payment details for
     * @param r signature r value
     * @param yParityAndS signature y parity and s value
     */
    function claimDeposit(
        Claim calldata claim,
        address buyer,
        bytes32 r,
        bytes32 yParityAndS
    ) external {
        _validateClaimSignature(claim, buyer, r, yParityAndS);

        address tokenAddress = claim.tokenAddress;
        uint256 tokenId = claim.tokenId;
        uint256 expiredTimestamp = claim.expiredTimestamp;

        // validate timestamp:
        // prevent signing claims that are too far in the future
        // still allows for maliciously pre-signing claims but narrows the
        // window down
        if (
            expiredTimestamp < block.timestamp
                || (expiredTimestamp - block.timestamp) > SIGNATURE_MAX_DURATION
        ) {
            revert ExpiredClaim();
        }

        // validate commitment:
        // validate that the claim is for the same block that the seller
        // committed
        ClaimCommitment memory commitment = commitments[tokenAddress][tokenId];
        if (uint256(commitment.blockNumber) != block.number) {
            revert InvalidCommitment();
        }
        if (commitment.buyer != buyer) {
            revert InvalidBuyer();
        }

        // validate deposit:
        // load deposit, check the balance, check the recipient owns the token,
        // and delete it
        Deposit memory buyerDeposit = deposits[buyer][tokenAddress][tokenId];

        uint256 balance = buyerDeposit.paymentBalance;
        // empty deposit means it has been claimed or withdrawn
        // deposit amount doesn't match the commitment amount, should fail

        if (balance == 0 || balance != commitment.depositAmount) {
            revert InvalidDeposit();
        }
        // validate that recipient now owns the token
        if (
            IERC721(tokenAddress).ownerOf(tokenId)
                != buyerDeposit.tokenRecipient
        ) {
            revert NotTokenOwner();
        }
        // clear the deposit
        delete deposits[buyer][claim.tokenAddress][claim.tokenId];
        // clear the commitment
        delete commitments[tokenAddress][tokenId];

        // pay the seller
        (bool succ, bytes memory reason) =
            commitment.seller.call{ value: balance }("");
        // if the payment fails, revert the transaction
        if (!succ) {
            assembly {
                revert(add(0x20, reason), mload(reason))
            }
        }
    }

    function _validateClaimSignature(
        Claim calldata claim,
        address buyer,
        bytes32 r,
        bytes32 yParityAndS
    ) internal {
        // calculate claim digest to validate signature
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        EIP712_CLAIM_TYPEHASH,
                        claim.tokenAddress,
                        claim.tokenId,
                        claim.expiredTimestamp
                    )
                )
            )
        );
        uint8 v;
        bytes32 s;
        assembly {
            // get the s value from packed yParityAndS
            s :=
                and(
                    yParityAndS,
                    0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
                )
            // get the yParity value; 27 if top bit of yParityAndS is not set,
            // 28 if it was
            v := add(27, gt(yParityAndS, s))
        }
        // validate the signature
        address signer = ecrecover(digest, v, r, s);
        if (signer != buyer) {
            revert InvalidSignature();
        }

        // validate that the signature has not been used before; mark it as used
        if (usedSignatures[digest]) {
            revert InvalidSignature();
        }
        usedSignatures[digest] = true;
    }
}
