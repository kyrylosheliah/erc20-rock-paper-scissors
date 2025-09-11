// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IMintable.sol";
import "./IBurnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title An ERC20 token implementation with role-based access control
/// @author
/// @notice Implements IERC20, IBurnable, role-restricted IMintable.
contract ERC20Token is IERC20, AccessControl, IMintable, IBurnable {

    string public name;

    string public symbol;

    uint8 public decimals = 18;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 public totalSupply;

    mapping(address => uint256) public balances;

    mapping(address => mapping(address => uint256)) public allowances;

    // --------------------
    // Role-based modifiers
    // --------------------

    modifier onlyAdmins() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "the caller is not an admin");
        _;
    }

    modifier onlyMinters() {
        require(hasRole(MINTER_ROLE, msg.sender), "the caller is not a minter");
        _;
    }

    // -----------
    // constructor
    // -----------

    /// @param name_ The name of the token (e.g., "Rock Paper Scissors Token")
    /// @param symbol_ The symbol of the token (e.g., "RPS")
    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
        // Grant the deployer the default admin role and minter role
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    // ---------
    // IMintable
    // ---------

    /// @notice Mint new tokens and assign them to a specified address
    /// @param account The recipient of the minted tokens
    /// @param amount The number of tokens to mint
    function mint(address account, uint256 amount) public onlyMinters {
        _mint(account, amount);
    }

    // ---------
    // IBurnable
    // ---------

    /// @notice Burn (destroy) tokens from the caller's balance
    /// @param amount The number of tokens to burn
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // ---------------------
    // IERC20 implementation
    // ---------------------

    /// @inheritdoc IERC20
    function transfer(address to, uint256 value) public virtual returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 value) external returns (bool) {
        // Solution 1?
        allowances[msg.sender][spender] = 0;
        // A race condition here:
        allowances[msg.sender][spender] = value;
        // Solution 2?
        // Change the interpretation of this operation interface to:
        // _allowances[msg.sender][spender] += value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        uint256 currentAllowance = allowances[from][msg.sender];
        require(currentAllowance >= value, "transfer exceeds allowance");

        allowances[from][msg.sender] = currentAllowance - value;
        _transfer(from, to, value);

        return true;
    }

    // already generated from a publicly declared totalSupply
    /// @inheritdoc IERC20
    // function totalSupply() external view returns (uint256) {
    //     return totalSupply;
    // }

    /// @inheritdoc IERC20
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) external view returns (uint256) {
        return allowances[owner][spender];
    }

    /// @inheritdoc IERC20
    // event Transfer(address indexed from, address indexed to, uint256 value);

    /// @inheritdoc IERC20
    // event Approval(address indexed owner, address indexed spender, uint256 value);

    // --------
    // Internal
    // --------

    /// @dev Internal function to mint tokens to an account
    /// @notice Mints from `address(0)`
    /// @param to The recipient of minted tokens
    /// @param amount The number of tokens to mint
    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "mint to zero address");

        balances[to] += amount;
        totalSupply += amount;

        emit Transfer(address(0), to, amount);
    }

    /// @dev Internal function to burn tokens from an account
    /// @notice Burns to `address(0)`
    /// @param account The address whose tokens will be burned
    /// @param amount The number of tokens to burn
    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "burn from zero address");
        require(balances[account] >= amount, "burn exceeds balance");

        balances[account] -= amount;
        totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    /// @dev Internal function to transfer tokens between accounts
    /// @param from The address sending tokens
    /// @param to The recipient address
    /// @param amount The number of tokens to transfer
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "transfer from zero address");
        require(to != address(0), "transfer to zero address");
        require(balances[from] >= amount, "insufficient balance");

        balances[from] -= amount;
        balances[to] += amount;

        emit Transfer(from, to, amount);
    }

}
