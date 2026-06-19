// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Escrow
 * @notice A simple three-party escrow for native ETH.
 *
 *         Roles
 *         ------
 *         buyer   — deposits funds and initiates the escrow.
 *         seller  — receives funds when the buyer (or arbiter) releases.
 *         arbiter — neutral third party that can release to seller or refund to buyer
 *                   in the event of a dispute.
 *
 *         Flow
 *         ----
 *         1. The buyer deploys the contract, naming a seller and an arbiter,
 *            then calls `deposit()` with the agreed ETH value.
 *         2. Happy path: buyer calls `release()` → seller receives the ETH.
 *         3. Dispute path: buyer calls `initiateDispute()`, then the arbiter
 *            calls either `release()` (to seller) or `refund()` (to buyer).
 *
 *         State machine
 *         -------------
 *         AWAITING_DEPOSIT → AWAITING_DELIVERY → COMPLETE
 *                                              ↘ REFUNDED
 *                                      (via DISPUTED)
 */
contract Escrow {
    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    enum State {
        AWAITING_DEPOSIT,  // Initial state; no funds held yet
        AWAITING_DELIVERY, // Funds deposited; waiting for release or dispute
        DISPUTED,          // Buyer opened a dispute; arbiter must resolve
        COMPLETE,          // Funds released to seller
        REFUNDED           // Funds returned to buyer
    }

    // -------------------------------------------------------------------------
    // State variables
    // -------------------------------------------------------------------------

    address public immutable buyer;
    address public immutable seller;
    address public immutable arbiter;

    uint256 public depositAmount;
    State   public currentState;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Deposited(address indexed buyer, uint256 amount);
    event Released(address indexed seller, uint256 amount);
    event Refunded(address indexed buyer, uint256 amount);
    event DisputeInitiated(address indexed buyer);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyBuyer() {
        require(msg.sender == buyer, "Escrow: caller is not the buyer");
        _;
    }

    modifier onlyArbiter() {
        require(msg.sender == arbiter, "Escrow: caller is not the arbiter");
        _;
    }

    modifier inState(State expected) {
        require(currentState == expected, "Escrow: invalid state for this action");
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @param _seller  Address that will receive funds upon release.
     * @param _arbiter Neutral party that resolves disputes.
     */
    constructor(address _seller, address _arbiter) {
        require(_seller  != address(0), "Escrow: seller is zero address");
        require(_arbiter != address(0), "Escrow: arbiter is zero address");
        require(_seller  != msg.sender, "Escrow: buyer and seller cannot be the same");
        require(_arbiter != msg.sender, "Escrow: buyer and arbiter cannot be the same");

        buyer   = msg.sender;
        seller  = _seller;
        arbiter = _arbiter;
        currentState = State.AWAITING_DEPOSIT;
    }

    // -------------------------------------------------------------------------
    // External functions
    // -------------------------------------------------------------------------

    /**
     * @notice Buyer deposits ETH into escrow.
     * @dev Must be called exactly once while in AWAITING_DEPOSIT state.
     *      The ETH value sent becomes the escrow amount.
     */
    function deposit()
        external
        payable
        onlyBuyer
        inState(State.AWAITING_DEPOSIT)
    {
        require(msg.value > 0, "Escrow: deposit must be greater than zero");
        depositAmount = msg.value;
        currentState  = State.AWAITING_DELIVERY;
        emit Deposited(buyer, msg.value);
    }

    /**
     * @notice Releases escrowed funds to the seller.
     * @dev Can be called by:
     *        - the buyer in AWAITING_DELIVERY state (happy-path approval), or
     *        - the arbiter in DISPUTED state (arbiter rules for seller).
     */
    function release() external {
        if (msg.sender == buyer) {
            require(
                currentState == State.AWAITING_DELIVERY,
                "Escrow: invalid state for this action"
            );
        } else if (msg.sender == arbiter) {
            require(
                currentState == State.DISPUTED,
                "Escrow: invalid state for this action"
            );
        } else {
            revert("Escrow: caller is not authorized to release");
        }

        currentState = State.COMPLETE;
        uint256 amount = depositAmount;
        depositAmount = 0; // zero before external call (checks-effects-interactions)

        (bool success, ) = seller.call{value: amount}("");
        require(success, "Escrow: ETH transfer to seller failed");

        emit Released(seller, amount);
    }

    /**
     * @notice Returns escrowed funds to the buyer.
     * @dev Can only be called by the arbiter while in DISPUTED state.
     *      The buyer cannot self-refund without opening a dispute first —
     *      this prevents the buyer from backing out of a completed delivery.
     */
    function refund()
        external
        onlyArbiter
        inState(State.DISPUTED)
    {
        currentState = State.REFUNDED;
        uint256 amount = depositAmount;
        depositAmount = 0; // zero before external call

        (bool success, ) = buyer.call{value: amount}("");
        require(success, "Escrow: ETH refund to buyer failed");

        emit Refunded(buyer, amount);
    }

    /**
     * @notice Buyer signals a dispute, escalating to the arbiter.
     * @dev Only valid while in AWAITING_DELIVERY state.
     */
    function initiateDispute()
        external
        onlyBuyer
        inState(State.AWAITING_DELIVERY)
    {
        currentState = State.DISPUTED;
        emit DisputeInitiated(buyer);
    }

    // -------------------------------------------------------------------------
    // Fallback: reject direct ETH sends (use deposit() instead)
    // -------------------------------------------------------------------------

    receive() external payable {
        revert("Escrow: use deposit()");
    }
}
