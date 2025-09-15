// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IMintable.sol";
import "./interfaces/IBurnable.sol";
import "./interfaces/IAccessControlErrors.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/// @title An ERC20 token implementation with role-based access control
/// @author
/// @notice Is Upgradeable by being Initializable. Implements role-restricted IMintable.
contract ERC20TokenUpgradeable is
    Initializable,
    AccessControlUpgradeable,
    IERC20,
    IERC20Errors,
    IAccessControlErrors,
    IMintable,
    IBurnable
{
    // -----------
    // Token state
    // -----------

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
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert AccessControlNotAdmin();
        }
        _;
    }

    modifier onlyMinters() {
        if (!hasRole(MINTER_ROLE, msg.sender)) {
            revert AccessControlNotMinter();
        }
        _;
    }

    // -----------
    // constructor
    // -----------

    /// @param name_ The name of the token (e.g., "Rock Paper Scissors Token")
    /// @param symbol_ The symbol of the token (e.g., "RPS")
    function ERC20TokenInitialize(string memory name_, string memory symbol_) public initializer {
        __ERC20Token_init(name_, symbol_);
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
        allowances[msg.sender][spender] = value;

        emit Approval(msg.sender, spender, value);

        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        uint256 currentAllowance = allowances[from][msg.sender];
        if (currentAllowance < value) revert ERC20InsufficientAllowance(msg.sender, currentAllowance, value);

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

    /// @param name_ The name of the token (e.g., "Rock Paper Scissors Token")
    /// @param symbol_ The symbol of the token (e.g., "RPS")
    function __ERC20Token_init(string memory name_, string memory symbol_) internal {
        name = name_;
        symbol = symbol_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    /// @dev Internal function to mint tokens to an account
    /// @notice Mints from `address(0)`
    /// @param to The recipient of minted tokens
    /// @param amount The number of tokens to mint
    function _mint(address to, uint256 amount) internal {
        if (to == address(0)) revert ERC20InvalidReceiver(to);

        balances[to] += amount;
        totalSupply += amount;

        emit Transfer(address(0), to, amount);
    }

    /// @dev Internal function to burn tokens from an account
    /// @notice Burns to `address(0)`
    /// @param account The address whose tokens will be burned
    /// @param amount The number of tokens to burn
    function _burn(address account, uint256 amount) internal {
        if (account == address(0)) revert ERC20InvalidSender(account);
        if (balances[account] < amount) revert ERC20InsufficientBalance(account, balances[account], amount);

        balances[account] -= amount;
        totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    /// @dev Internal function to transfer tokens between accounts
    /// @param from The address sending tokens
    /// @param to The recipient address
    /// @param amount The number of tokens to transfer
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0)) revert ERC20InvalidSender(from);
        if (to == address(0)) revert ERC20InvalidReceiver(to);
        if (balances[from] < amount) revert ERC20InsufficientBalance(from, balances[from], amount);

        balances[from] -= amount;
        balances[to] += amount;

        emit Transfer(from, to, amount);
    }

}
