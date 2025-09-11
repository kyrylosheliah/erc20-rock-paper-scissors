// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IMintable.sol";
import "./IBurnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title RPSToken - An ERC20 token with role-based access control
/// @author
/// @notice Implements IERC20, IBurnable, role-restricted minting.
contract RPSToken is IERC20, AccessControl, IMintable, IBurnable {

    string private _name;

    string private _symbol;

    uint8 private _decimals = 18;

    bytes32 private constant _MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    /// @param name The name of the token (e.g., "Rock Paper Scissors Token")
    /// @param symbol The symbol of the token (e.g., "RPS")
    constructor(string memory name, string memory symbol) {
        _name = name;
        _symbol = symbol;
        // Grant the deployer the default admin role and minter role
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(_MINTER_ROLE, msg.sender);
    }

    // -------------------
    // Minting and burning
    // -------------------

    /// @notice Mint new tokens and assign them to a specified address
    /// @param to The recipient of the minted tokens
    /// @param amount The number of tokens to mint
    function mint(address to, uint256 amount) public {
        require(hasRole(_MINTER_ROLE, msg.sender), "the caller is not a minter");
        _mint(to, amount);
    }

    /// @notice Burn (destroy) tokens from the caller's balance
    /// @param amount The number of tokens to burn
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // ---------------------
    // IERC20 implementation
    // ---------------------

    /// @inheritdoc IERC20
    // event Transfer(address indexed from, address indexed to, uint256 value);

    /// @inheritdoc IERC20
    // event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @inheritdoc IERC20
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 value) external returns (bool) {
        // Solution 1?
        _allowances[msg.sender][spender] = 0;
        // A race condition here:
        _allowances[msg.sender][spender] = value;
        // Solution 2?
        // Change the interpretation of this operation interface to:
        // _allowances[msg.sender][spender] += value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= value, "transfer exceeds allowance");

        _allowances[from][msg.sender] = currentAllowance - value;
        _transfer(from, to, value);
        return true;
    }

    /// @inheritdoc IERC20
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    // ---------------------
    // Internal functions
    // ---------------------

    /// @dev Internal function to mint tokens to an account
    /// @notice Mints from `address(0)`
    /// @param to The recipient of minted tokens
    /// @param amount The number of tokens to mint
    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "mint to zero address");

        _balances[to] += amount;
        _totalSupply += amount;

        emit Transfer(address(0), to, amount);
    }

    /// @dev Internal function to burn tokens from an account
    /// @notice Burns to `address(0)`
    /// @param account The address whose tokens will be burned
    /// @param amount The number of tokens to burn
    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "burn from zero address");
        require(_balances[account] >= amount, "burn exceeds balance");

        _balances[account] -= amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    /// @dev Internal function to transfer tokens between accounts
    /// @param from The address sending tokens
    /// @param to The recipient address
    /// @param amount The number of tokens to transfer
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "transfer from zero address");
        require(to != address(0), "transfer to zero address");
        require(_balances[from] >= amount, "insufficient balance");

        _balances[from] -= amount;
        _balances[to] += amount;

        emit Transfer(from, to, amount);
    }

}
