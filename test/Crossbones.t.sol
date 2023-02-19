// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseTest } from "test/BaseTest.sol";
import { Crossbones } from "../src/Crossbones.sol";
import { Claim, Deposit, ClaimCommitment } from "../src/lib/Structs.sol";
import { TestERC721 } from "./helpers/TestERC721.sol";

contract CrossbonesTest is BaseTest {
    Crossbones test;
    TestERC721 token;
    bool shouldRevert;

    function setUp() public virtual override {
        super.setUp();
        test = new Crossbones();
        token = new TestERC721();
    }

    function testDeposit() public {
        uint256 AMOUNT = 100;
        test.deposit{ value: AMOUNT }(address(token), 1, address(this));
        (address recipient, uint256 amount) =
            test.deposits(address(this), address(token), 1);
        assertEq(recipient, address(this));
        assertEq(amount, AMOUNT);
    }

    function testDeposit_InvalidDeposit() public {
        vm.expectRevert(Crossbones.InvalidDeposit.selector);
        test.deposit{ value: 0 }(address(token), 1, address(this));
    }

    function testDeposit_DepositExists() public {
        uint256 AMOUNT = 100;
        test.deposit{ value: AMOUNT }(address(token), 1, address(this));
        vm.expectRevert(Crossbones.DepositExists.selector);
        test.deposit{ value: AMOUNT }(address(token), 1, address(this));
    }

    function _deposit(
        address tokenAddress,
        uint256 id,
        uint256 amount,
        address buyer
    ) internal {
        vm.deal(buyer, amount);
        vm.prank(buyer);
        test.deposit{ value: amount }(tokenAddress, id, buyer);
    }

    function _deposit(uint256 amount, address buyer) internal {
        _deposit(address(token), 1, amount, buyer);
    }

    function testCommitClaim() public {
        token.mint(address(this), 1);
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, address(this));

        test.commitClaim(address(token), 1, address(this), 100);

        (
            address seller,
            uint256 blockNumber,
            address buyer,
            uint256 depositAmount
        ) = test.commitments(address(token), 1);
        assertEq(seller, address(this));
        assertEq(blockNumber, block.number);
        assertEq(buyer, address(this));
        assertEq(depositAmount, 100);
    }

    function testCommitClaim_ActiveCommitment() public {
        token.mint(address(this), 1);
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, address(this));

        test.commitClaim(address(token), 1, address(this), 100);

        vm.expectRevert(Crossbones.ActiveCommitment.selector);
        test.commitClaim(address(token), 1, address(this), 100);
    }

    function testCommitClaim_InvalidCommitment() public {
        token.mint(address(this), 1);
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, address(this));

        vm.expectRevert(Crossbones.InvalidCommitment.selector);
        test.commitClaim(address(token), 1, address(this), 1);
    }

    function testCommitClaim_notTokenowner() public {
        token.mint(address(123), 1);
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, address(this));

        vm.expectRevert(Crossbones.NotTokenOwner.selector);
        test.commitClaim(address(token), 1, address(this), 100);
    }

    function testCommitClaim(
        address seller,
        address buyer,
        uint96 depositAmount,
        uint256 blockNum
    ) public {
        depositAmount = uint96(bound(depositAmount, 1, type(uint96).max));
        blockNum = uint96(bound(blockNum, 1, type(uint96).max));
        seller = address(uint160(bound(uint160(seller), 1, type(uint160).max)));
        _deposit(depositAmount, buyer);

        token.mint(seller, 1);
        vm.roll(blockNum);
        vm.prank(seller);
        test.commitClaim(address(token), 1, buyer, depositAmount);

        (
            address _seller,
            uint256 _blockNum,
            address _buyer,
            uint256 _depositAmount
        ) = test.commitments(address(token), 1);
        assertEq(_seller, seller);
        assertEq(_blockNum, blockNum);
        assertEq(_buyer, buyer);
        assertEq(_depositAmount, depositAmount);
    }

    function testWithdrawDeposit() public {
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, address(this));

        test.withdrawDeposit(address(token), 1);

        (address recipient, uint256 amount) =
            test.deposits(address(this), address(token), 1);
        assertEq(recipient, address(0));
        assertEq(amount, 0);
    }

    function testWithdrawDeposit_TransferFail() public {
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, address(this));
        shouldRevert = true;
        vm.expectRevert("revertooooor");
        test.withdrawDeposit(address(token), 1);
    }

    function testWithdrawDeposit_NoDeposit() public {
        vm.expectRevert(Crossbones.InvalidDeposit.selector);
        test.withdrawDeposit(address(token), 1);
    }

    function testClaimDeposit() public {
        (address buyer, uint256 key) = makeAddrAndKey("buyer");
        address seller = makeAddr("seller");
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, buyer);

        token.mint(seller, 1);
        vm.startPrank(seller);
        test.commitClaim(address(token), 1, buyer, AMOUNT);
        token.transferFrom(seller, buyer, 1);
        Claim memory claim = Claim({
            tokenAddress: address(token),
            tokenId: 1,
            expiredTimestamp: block.timestamp + 100
        });
        (bytes32 r, bytes32 yParityAndS) = signClaim(claim, key);

        test.claimDeposit(claim, buyer, r, yParityAndS);
        assertEq(seller.balance, AMOUNT);
        (address recipient, uint256 amount) =
            test.deposits(buyer, address(token), 1);
        assertEq(recipient, address(0));
        assertEq(amount, 0);
    }

    function testClaimDeposit_TransferRevert() public {
        (address buyer, uint256 key) = makeAddrAndKey("buyer");
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, buyer);

        token.mint(address(this), 1);
        vm.startPrank(address(this));
        test.commitClaim(address(token), 1, buyer, AMOUNT);
        token.transferFrom(address(this), buyer, 1);
        Claim memory claim = Claim({
            tokenAddress: address(token),
            tokenId: 1,
            expiredTimestamp: block.timestamp + 100
        });
        (bytes32 r, bytes32 yParityAndS) = signClaim(claim, key);
        shouldRevert = true;
        vm.expectRevert("revertooooor");

        test.claimDeposit(claim, buyer, r, yParityAndS);
    }

    function testClaimDeposit_UsedSignature() public {
        (address buyer, uint256 key) = makeAddrAndKey("buyer");
        address seller = makeAddr("seller");
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, buyer);

        token.mint(seller, 1);
        vm.startPrank(seller);
        test.commitClaim(address(token), 1, buyer, AMOUNT);
        token.transferFrom(seller, buyer, 1);
        Claim memory claim = Claim({
            tokenAddress: address(token),
            tokenId: 1,
            expiredTimestamp: block.timestamp + 100
        });
        (bytes32 r, bytes32 yParityAndS) = signClaim(claim, key);

        test.claimDeposit(claim, buyer, r, yParityAndS);
        vm.stopPrank();

        _deposit(AMOUNT, buyer);
        vm.prank(buyer);
        token.transferFrom(buyer, seller, 1);

        vm.startPrank(seller);
        test.commitClaim(address(token), 1, buyer, AMOUNT);
        vm.expectRevert(Crossbones.InvalidSignature.selector);
        test.claimDeposit(claim, buyer, r, yParityAndS);
    }

    function testClaim_ExpiredClaim() public {
        (address buyer, uint256 key) = makeAddrAndKey("buyer");
        address seller = makeAddr("seller");
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, buyer);

        token.mint(seller, 1);
        vm.startPrank(seller);
        test.commitClaim(address(token), 1, buyer, AMOUNT);
        token.transferFrom(seller, buyer, 1);
        Claim memory claim = Claim({
            tokenAddress: address(token),
            tokenId: 1,
            expiredTimestamp: block.timestamp + 1e18
        });
        (bytes32 r, bytes32 yParityAndS) = signClaim(claim, key);
        vm.expectRevert(Crossbones.ExpiredClaim.selector);
        test.claimDeposit(claim, buyer, r, yParityAndS);
    }

    function testClaim_InvalidCommitment_BlockNumber() public {
        (address buyer, uint256 key) = makeAddrAndKey("buyer");
        address seller = makeAddr("seller");
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, buyer);

        token.mint(seller, 1);
        vm.startPrank(seller);
        test.commitClaim(address(token), 1, buyer, AMOUNT);
        vm.roll(block.number + 1);
        token.transferFrom(seller, buyer, 1);
        Claim memory claim = Claim({
            tokenAddress: address(token),
            tokenId: 1,
            expiredTimestamp: block.timestamp + 100
        });
        (bytes32 r, bytes32 yParityAndS) = signClaim(claim, key);
        vm.expectRevert(Crossbones.InvalidCommitment.selector);
        test.claimDeposit(claim, buyer, r, yParityAndS);
    }

    function testClaim_InvalidBuyer() public {
        (address buyer,) = makeAddrAndKey("buyer");
        (address fakeBuyer, uint256 fakeKey) = makeAddrAndKey("fake buyer");
        address seller = makeAddr("seller");
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, buyer);

        token.mint(seller, 1);
        vm.startPrank(seller);
        test.commitClaim(address(token), 1, buyer, AMOUNT);
        token.transferFrom(seller, buyer, 1);
        Claim memory claim = Claim({
            tokenAddress: address(token),
            tokenId: 1,
            expiredTimestamp: block.timestamp + 100
        });
        (bytes32 r, bytes32 yParityAndS) = signClaim(claim, fakeKey);
        vm.expectRevert(Crossbones.InvalidBuyer.selector);
        test.claimDeposit(claim, fakeBuyer, r, yParityAndS);
    }

    function testClaim_InvalidDeposit_Zero() public {
        (address buyer, uint256 key) = makeAddrAndKey("buyer");
        address seller = makeAddr("seller");
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, buyer);

        token.mint(seller, 1);
        vm.startPrank(seller);
        test.commitClaim(address(token), 1, buyer, AMOUNT);
        token.transferFrom(seller, buyer, 1);
        Claim memory claim = Claim({
            tokenAddress: address(token),
            tokenId: 1,
            expiredTimestamp: block.timestamp + 100
        });
        (bytes32 r, bytes32 yParityAndS) = signClaim(claim, key);
        vm.stopPrank();
        vm.prank(buyer);
        test.withdrawDeposit(address(token), 1);
        vm.prank(seller);
        vm.expectRevert(Crossbones.InvalidDeposit.selector);
        test.claimDeposit(claim, buyer, r, yParityAndS);
    }

    function testClaim_NotTokenOwner() public {
        (address buyer, uint256 key) = makeAddrAndKey("buyer");
        address seller = makeAddr("seller");
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, buyer);

        token.mint(seller, 1);
        vm.startPrank(seller);
        test.commitClaim(address(token), 1, buyer, AMOUNT);
        Claim memory claim = Claim({
            tokenAddress: address(token),
            tokenId: 1,
            expiredTimestamp: block.timestamp + 100
        });
        (bytes32 r, bytes32 yParityAndS) = signClaim(claim, key);
        vm.expectRevert(Crossbones.NotTokenOwner.selector);
        test.claimDeposit(claim, buyer, r, yParityAndS);
    }

    function testClaim_InvalidDeposit_Different() public {
        (address buyer, uint256 key) = makeAddrAndKey("buyer");
        address seller = makeAddr("seller");
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, buyer);

        token.mint(seller, 1);
        vm.startPrank(seller);
        test.commitClaim(address(token), 1, buyer, AMOUNT);
        token.transferFrom(seller, buyer, 1);
        Claim memory claim = Claim({
            tokenAddress: address(token),
            tokenId: 1,
            expiredTimestamp: block.timestamp + 100
        });
        (bytes32 r, bytes32 yParityAndS) = signClaim(claim, key);
        vm.stopPrank();
        vm.startPrank(buyer);
        test.withdrawDeposit(address(token), 1);
        test.deposit{ value: AMOUNT - 1 }(address(token), 1, buyer);
        vm.stopPrank();
        vm.prank(seller);
        vm.expectRevert(Crossbones.InvalidDeposit.selector);
        test.claimDeposit(claim, buyer, r, yParityAndS);
    }

    function testClaim_InvalidSignature() public {
        (address buyer,) = makeAddrAndKey("buyer");
        address seller = makeAddr("seller");
        uint256 AMOUNT = 100;
        _deposit(AMOUNT, buyer);

        token.mint(seller, 1);
        vm.startPrank(seller);
        test.commitClaim(address(token), 1, buyer, AMOUNT);
        token.transferFrom(seller, buyer, 1);
        Claim memory claim = Claim({
            tokenAddress: address(token),
            tokenId: 1,
            expiredTimestamp: block.timestamp + 100
        });
        (bytes32 r, bytes32 yParityAndS) = signClaim(claim, 123);
        vm.expectRevert(Crossbones.InvalidSignature.selector);
        test.claimDeposit(claim, buyer, r, yParityAndS);
    }

    function signClaim(Claim memory claim, uint256 key)
        internal
        view
        returns (bytes32, bytes32)
    {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                test.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        test.EIP712_CLAIM_TYPEHASH(),
                        claim.tokenAddress,
                        claim.tokenId,
                        claim.expiredTimestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        bytes32 yParityAndS;

        assembly {
            let yParity := eq(v, 28)
            yParityAndS := or(shl(255, yParity), s)
        }

        return (r, yParityAndS);
    }

    receive() external payable {
        if (shouldRevert) {
            revert("revertooooor");
        }
    }
}
