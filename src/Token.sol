// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Token
 * @notice A minimal ERC-20 implementation written from scratch.
 *         Demonstrates the core ERC-20 standard: balances, allowances,
 *         transfer, approve, and transferFrom.
 * @dev Follows the ERC-20 specification (EIP-20). No external dependencies.
 */
contract Token {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    /// @dev owner address => token balance
    mapping(address => uint256) private _balances;

    /// @dev owner address => spender address => approved amount
    mapping(address => mapping(address => uint256)) private _allowances;

    // -------------------------------------------------------------------------
    // Events (required by ERC-20 spec)
    // -------------------------------------------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @param _name    Human-readable token name (e.g. "MyToken").
     * @param _symbol  Token ticker symbol (e.g. "MTK").
     * @param initialSupply Amount of tokens minted to the deployer, in whole
     *                      tokens (the contract scales by 10**18 internally).
     */
    constructor(string memory _name, string memory _symbol, uint256 initialSupply) {
        name = _name;
        symbol = _symbol;
        _mint(msg.sender, initialSupply * (10 ** decimals));
    }

    // -------------------------------------------------------------------------
    // ERC-20 view functions
    // -------------------------------------------------------------------------

    /// @notice Returns the token balance of `account`.
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    /// @notice Returns the amount that `spender` is allowed to spend on behalf of `owner`.
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    // -------------------------------------------------------------------------
    // ERC-20 mutating functions
    // -------------------------------------------------------------------------

    /**
     * @notice Transfers `amount` tokens from the caller to `to`.
     * @return True on success (reverts on failure).
     */
    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @notice Approves `spender` to spend up to `amount` tokens on behalf of the caller.
     * @return True on success.
     */
    function approve(address spender, uint256 amount) public returns (bool) {
        require(spender != address(0), "Token: approve to the zero address");
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Transfers `amount` tokens from `from` to `to` using the caller's allowance.
     * @return True on success.
     */
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "Token: insufficient allowance");
        // Decrease allowance before transfer to prevent reentrancy concerns
        _allowances[from][msg.sender] = currentAllowance - amount;
        _transfer(from, to, amount);
        return true;
    }

    // -------------------------------------------------------------------------
    // Public mint (demo only — a production token would restrict this)
    // -------------------------------------------------------------------------

    /**
     * @notice Mints `amount` tokens (in base units, i.e. including decimals) to `to`.
     * @dev In a real token this would be restricted (e.g. onlyOwner). Left open
     *      here for ease of testing.
     */
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Token: transfer from the zero address");
        require(to != address(0), "Token: transfer to the zero address");
        require(_balances[from] >= amount, "Token: insufficient balance");

        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "Token: mint to the zero address");
        totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}
