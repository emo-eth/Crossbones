// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseTest } from "test/BaseTest.sol";
import { Crossbones } from "../src/Crossbones.sol";
import { Claim, Deposit, ClaimCommitment } from "../src/lib/Structs.sol";
import { TestERC721 } from "./helpers/TestERC721.sol";

contract CrossbonesTest is BaseTest {
    Crossbones test;
    TestERC721 token;

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

    function testCommitClaim(
        address seller,
        address buyer,
        uint96 depositAmount,
        uint256 blockNum
    ) public {
        depositAmount = uint96(bound(depositAmount, 1, type(uint96).max));
        blockNum = uint96(bound(blockNum, 1, type(uint96).max));
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
}
