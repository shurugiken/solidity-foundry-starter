// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Token.sol";

/**
 * @title TokenTest
 * @notice Unit tests for the Token ERC-20 contract.
 */
contract TokenTest is Test {
    Token internal token;

    address internal alice = makeAddr("alice");
    address internal bob   = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant INITIAL_SUPPLY = 1_000_000; // whole tokens
    uint256 internal constant DECIMALS_FACTOR = 10 ** 18;

    function setUp() public {
        // Deploy as alice so she holds the initial supply
        vm.prank(alice);
        token = new Token("MyToken", "MTK", INITIAL_SUPPLY);
    }

    // -------------------------------------------------------------------------
    // Deployment / metadata
    // -------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "MyToken");
        assertEq(token.symbol(), "MTK");
        assertEq(token.decimals(), 18);
    }

    function test_initialSupplyMintedToDeployer() public view {
        uint256 expected = INITIAL_SUPPLY * DECIMALS_FACTOR;
        assertEq(token.totalSupply(), expected);
        assertEq(token.balanceOf(alice), expected);
        assertEq(token.balanceOf(bob), 0);
    }

    // -------------------------------------------------------------------------
    // transfer
    // -------------------------------------------------------------------------

    function test_transfer_succeeds() public {
        uint256 amount = 500 * DECIMALS_FACTOR;
        vm.prank(alice);
        bool ok = token.transfer(bob, amount);

        assertTrue(ok);
        assertEq(token.balanceOf(alice), (INITIAL_SUPPLY * DECIMALS_FACTOR) - amount);
        assertEq(token.balanceOf(bob), amount);
    }

    function test_transfer_emitsTransferEvent() public {
        uint256 amount = 100 * DECIMALS_FACTOR;
        vm.expectEmit(true, true, false, true, address(token));
        emit Token.Transfer(alice, bob, amount);

        vm.prank(alice);
        token.transfer(bob, amount);
    }

    function test_transfer_revertsOnInsufficientBalance() public {
        uint256 tooMuch = (INITIAL_SUPPLY + 1) * DECIMALS_FACTOR;
        vm.prank(alice);
        vm.expectRevert("Token: insufficient balance");
        token.transfer(bob, tooMuch);
    }

    function test_transfer_revertsToZeroAddress() public {
        vm.prank(alice);
        vm.expectRevert("Token: transfer to the zero address");
        token.transfer(address(0), 1);
    }

    function test_transfer_fullBalance() public {
        uint256 all = token.balanceOf(alice);
        vm.prank(alice);
        token.transfer(bob, all);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), all);
    }

    // -------------------------------------------------------------------------
    // approve / allowance
    // -------------------------------------------------------------------------

    function test_approve_setsAllowance() public {
        uint256 amount = 200 * DECIMALS_FACTOR;
        vm.prank(alice);
        bool ok = token.approve(bob, amount);

        assertTrue(ok);
        assertEq(token.allowance(alice, bob), amount);
    }

    function test_approve_emitsApprovalEvent() public {
        uint256 amount = 50 * DECIMALS_FACTOR;
        vm.expectEmit(true, true, false, true, address(token));
        emit Token.Approval(alice, bob, amount);

        vm.prank(alice);
        token.approve(bob, amount);
    }

    function test_approve_overwritesPreviousAllowance() public {
        vm.startPrank(alice);
        token.approve(bob, 100 * DECIMALS_FACTOR);
        token.approve(bob, 300 * DECIMALS_FACTOR);
        vm.stopPrank();

        assertEq(token.allowance(alice, bob), 300 * DECIMALS_FACTOR);
    }

    function test_approve_revertsOnZeroSpender() public {
        vm.prank(alice);
        vm.expectRevert("Token: approve to the zero address");
        token.approve(address(0), 100);
    }

    // -------------------------------------------------------------------------
    // transferFrom
    // -------------------------------------------------------------------------

    function test_transferFrom_succeeds() public {
        uint256 amount = 300 * DECIMALS_FACTOR;

        vm.prank(alice);
        token.approve(bob, amount);

        vm.prank(bob);
        bool ok = token.transferFrom(alice, carol, amount);

        assertTrue(ok);
        assertEq(token.balanceOf(alice), (INITIAL_SUPPLY * DECIMALS_FACTOR) - amount);
        assertEq(token.balanceOf(carol), amount);
        // Allowance consumed
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_transferFrom_emitsTransferEvent() public {
        uint256 amount = 10 * DECIMALS_FACTOR;
        vm.prank(alice);
        token.approve(bob, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit Token.Transfer(alice, carol, amount);

        vm.prank(bob);
        token.transferFrom(alice, carol, amount);
    }

    function test_transferFrom_revertsOnInsufficientAllowance() public {
        uint256 approved = 100 * DECIMALS_FACTOR;
        uint256 overSpend = 101 * DECIMALS_FACTOR;

        vm.prank(alice);
        token.approve(bob, approved);

        vm.prank(bob);
        vm.expectRevert("Token: insufficient allowance");
        token.transferFrom(alice, carol, overSpend);
    }

    function test_transferFrom_revertsWithNoAllowance() public {
        vm.prank(bob);
        vm.expectRevert("Token: insufficient allowance");
        token.transferFrom(alice, carol, 1);
    }

    function test_transferFrom_partialSpend_leavesRemainingAllowance() public {
        uint256 approved = 500 * DECIMALS_FACTOR;
        uint256 spend    = 200 * DECIMALS_FACTOR;

        vm.prank(alice);
        token.approve(bob, approved);

        vm.prank(bob);
        token.transferFrom(alice, carol, spend);

        assertEq(token.allowance(alice, bob), approved - spend);
    }

    // -------------------------------------------------------------------------
    // mint
    // -------------------------------------------------------------------------

    function test_mint_increasesTotalSupplyAndBalance() public {
        uint256 mintAmount = 5_000 * DECIMALS_FACTOR;
        uint256 supplyBefore = token.totalSupply();

        token.mint(bob, mintAmount);

        assertEq(token.totalSupply(), supplyBefore + mintAmount);
        assertEq(token.balanceOf(bob), mintAmount);
    }

    function test_mint_revertsToZeroAddress() public {
        vm.expectRevert("Token: mint to the zero address");
        token.mint(address(0), 1);
    }
}
