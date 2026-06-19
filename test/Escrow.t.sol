// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Escrow.sol";

/**
 * @title EscrowTest
 * @notice Unit tests for the Escrow contract.
 *
 *         Covers:
 *         - Happy path: deposit → release (buyer approves)
 *         - Dispute path: deposit → initiateDispute → arbiter releases
 *         - Dispute path: deposit → initiateDispute → arbiter refunds
 *         - Access control: unauthorized callers are rejected
 *         - Revert cases: wrong state transitions, zero-value deposits
 */
contract EscrowTest is Test {
    Escrow internal escrow;

    address internal buyer   = makeAddr("buyer");
    address internal seller  = makeAddr("seller");
    address internal arbiter = makeAddr("arbiter");
    address internal stranger = makeAddr("stranger");

    uint256 internal constant DEPOSIT = 1 ether;

    function setUp() public {
        // Fund buyer, and stranger (so the unauthorized-deposit test reaches the
        // onlyBuyer check instead of reverting on insufficient balance for the send).
        vm.deal(buyer, 10 ether);
        vm.deal(stranger, 10 ether);

        // Deploy escrow as buyer
        vm.prank(buyer);
        escrow = new Escrow(seller, arbiter);
    }

    // -------------------------------------------------------------------------
    // Constructor / initial state
    // -------------------------------------------------------------------------

    function test_initialState() public view {
        assertEq(escrow.buyer(),   buyer);
        assertEq(escrow.seller(),  seller);
        assertEq(escrow.arbiter(), arbiter);
        assertEq(escrow.depositAmount(), 0);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.AWAITING_DEPOSIT));
    }

    function test_constructor_revertsOnZeroSeller() public {
        vm.prank(buyer);
        vm.expectRevert("Escrow: seller is zero address");
        new Escrow(address(0), arbiter);
    }

    function test_constructor_revertsOnZeroArbiter() public {
        vm.prank(buyer);
        vm.expectRevert("Escrow: arbiter is zero address");
        new Escrow(seller, address(0));
    }

    function test_constructor_revertsWhenBuyerIsSeller() public {
        vm.prank(buyer);
        vm.expectRevert("Escrow: buyer and seller cannot be the same");
        new Escrow(buyer, arbiter);
    }

    function test_constructor_revertsWhenBuyerIsArbiter() public {
        vm.prank(buyer);
        vm.expectRevert("Escrow: buyer and arbiter cannot be the same");
        new Escrow(seller, buyer);
    }

    // -------------------------------------------------------------------------
    // deposit()
    // -------------------------------------------------------------------------

    function test_deposit_succeeds() public {
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        assertEq(escrow.depositAmount(), DEPOSIT);
        assertEq(address(escrow).balance, DEPOSIT);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.AWAITING_DELIVERY));
    }

    function test_deposit_emitsDepositedEvent() public {
        vm.expectEmit(true, false, false, true, address(escrow));
        emit Escrow.Deposited(buyer, DEPOSIT);

        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();
    }

    function test_deposit_revertsOnZeroValue() public {
        vm.prank(buyer);
        vm.expectRevert("Escrow: deposit must be greater than zero");
        escrow.deposit{value: 0}();
    }

    function test_deposit_revertsIfNotBuyer() public {
        vm.prank(stranger);
        vm.expectRevert("Escrow: caller is not the buyer");
        escrow.deposit{value: DEPOSIT}();
    }

    function test_deposit_revertsIfAlreadyDeposited() public {
        vm.startPrank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.expectRevert("Escrow: invalid state for this action");
        escrow.deposit{value: DEPOSIT}();
        vm.stopPrank();
    }

    function test_deposit_revertsOnDirectEthSend() public {
        vm.prank(buyer);
        vm.expectRevert("Escrow: use deposit()");
        (bool ok,) = address(escrow).call{value: DEPOSIT}("");
        // ok will be false because the call reverted; assert for clarity
        assertFalse(ok);
    }

    // -------------------------------------------------------------------------
    // release() — happy path (buyer releases directly)
    // -------------------------------------------------------------------------

    function test_release_byBuyer_transfersFundsToSeller() public {
        uint256 sellerBefore = seller.balance;

        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.prank(buyer);
        escrow.release();

        assertEq(seller.balance, sellerBefore + DEPOSIT);
        assertEq(address(escrow).balance, 0);
        assertEq(escrow.depositAmount(), 0);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.COMPLETE));
    }

    function test_release_byBuyer_emitsReleasedEvent() public {
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.expectEmit(true, false, false, true, address(escrow));
        emit Escrow.Released(seller, DEPOSIT);

        vm.prank(buyer);
        escrow.release();
    }

    function test_release_byBuyer_revertsIfNotDeposited() public {
        // State is AWAITING_DEPOSIT, not AWAITING_DELIVERY
        vm.prank(buyer);
        vm.expectRevert("Escrow: invalid state for this action");
        escrow.release();
    }

    function test_release_revertsIfCalledByStranger() public {
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.prank(stranger);
        vm.expectRevert("Escrow: caller is not authorized to release");
        escrow.release();
    }

    function test_release_revertsIfCalledBySellerDirectly() public {
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.prank(seller);
        vm.expectRevert("Escrow: caller is not authorized to release");
        escrow.release();
    }

    // -------------------------------------------------------------------------
    // initiateDispute()
    // -------------------------------------------------------------------------

    function test_initiateDispute_setsDisputedState() public {
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.prank(buyer);
        escrow.initiateDispute();

        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.DISPUTED));
    }

    function test_initiateDispute_emitsEvent() public {
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.expectEmit(true, false, false, false, address(escrow));
        emit Escrow.DisputeInitiated(buyer);

        vm.prank(buyer);
        escrow.initiateDispute();
    }

    function test_initiateDispute_revertsIfNotBuyer() public {
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.prank(stranger);
        vm.expectRevert("Escrow: caller is not the buyer");
        escrow.initiateDispute();
    }

    function test_initiateDispute_revertsBeforeDeposit() public {
        // State is AWAITING_DEPOSIT
        vm.prank(buyer);
        vm.expectRevert("Escrow: invalid state for this action");
        escrow.initiateDispute();
    }

    // -------------------------------------------------------------------------
    // release() — dispute path (arbiter releases to seller)
    // -------------------------------------------------------------------------

    function test_release_byArbiter_afterDispute_transfersToSeller() public {
        uint256 sellerBefore = seller.balance;

        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.prank(buyer);
        escrow.initiateDispute();

        vm.prank(arbiter);
        escrow.release();

        assertEq(seller.balance, sellerBefore + DEPOSIT);
        assertEq(address(escrow).balance, 0);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.COMPLETE));
    }

    function test_release_byArbiter_revertsIfNotDisputed() public {
        // Arbiter cannot call release while state is AWAITING_DELIVERY
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.prank(arbiter);
        vm.expectRevert("Escrow: invalid state for this action");
        escrow.release();
    }

    // -------------------------------------------------------------------------
    // refund() — dispute path (arbiter refunds to buyer)
    // -------------------------------------------------------------------------

    function test_refund_byArbiter_afterDispute_returnsEthToBuyer() public {
        uint256 buyerBefore = buyer.balance; // already deposited DEPOSIT

        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.prank(buyer);
        escrow.initiateDispute();

        vm.prank(arbiter);
        escrow.refund();

        // Buyer gets their ETH back
        assertEq(buyer.balance, buyerBefore); // net zero (deposited then refunded)
        assertEq(address(escrow).balance, 0);
        assertEq(escrow.depositAmount(), 0);
        assertEq(uint256(escrow.currentState()), uint256(Escrow.State.REFUNDED));
    }

    function test_refund_byArbiter_emitsRefundedEvent() public {
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.prank(buyer);
        escrow.initiateDispute();

        vm.expectEmit(true, false, false, true, address(escrow));
        emit Escrow.Refunded(buyer, DEPOSIT);

        vm.prank(arbiter);
        escrow.refund();
    }

    function test_refund_revertsIfNotArbiter() public {
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.prank(buyer);
        escrow.initiateDispute();

        vm.prank(stranger);
        vm.expectRevert("Escrow: caller is not the arbiter");
        escrow.refund();
    }

    function test_refund_revertsIfBuyerCallsDirectly() public {
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.prank(buyer);
        escrow.initiateDispute();

        vm.prank(buyer);
        vm.expectRevert("Escrow: caller is not the arbiter");
        escrow.refund();
    }

    function test_refund_revertsIfNotDisputed() public {
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        // No dispute initiated — state is AWAITING_DELIVERY
        vm.prank(arbiter);
        vm.expectRevert("Escrow: invalid state for this action");
        escrow.refund();
    }

    // -------------------------------------------------------------------------
    // No double-spend: actions after terminal state
    // -------------------------------------------------------------------------

    function test_cannotReleaseAfterComplete() public {
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.prank(buyer);
        escrow.release(); // → COMPLETE

        vm.prank(buyer);
        vm.expectRevert("Escrow: invalid state for this action");
        escrow.release();
    }

    function test_cannotRefundAfterRefunded() public {
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.prank(buyer);
        escrow.initiateDispute();

        vm.prank(arbiter);
        escrow.refund(); // → REFUNDED

        vm.prank(arbiter);
        vm.expectRevert("Escrow: invalid state for this action");
        escrow.refund();
    }

    function test_cannotDepositAfterRefunded() public {
        vm.prank(buyer);
        escrow.deposit{value: DEPOSIT}();

        vm.prank(buyer);
        escrow.initiateDispute();

        vm.prank(arbiter);
        escrow.refund();

        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        vm.expectRevert("Escrow: invalid state for this action");
        escrow.deposit{value: DEPOSIT}();
    }
}
