// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IMintable.sol";
import "./IBurnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract RPSToken is IERC20, AccessControl, IMintable, IBurnable {

    string public name;
    string public symbol;
    uint8 public decimals = 18;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        // Grant the deployer the default admin role and minter role
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function mint(address _to, uint256 _amount) public {
        require(hasRole(MINTER_ROLE, msg.sender), "the caller is not a minter");
        _mint(_to, _amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // IERC20 implementation

    // // @dev Emitted when `value` tokens are moved
    // event Transfer(address indexed from, address indexed to, uint256 value);

    // // @dev Emitted when the allowance of a `spender` approved by an `owner`
    // event Approval(address indexed owner, address indexed spender, uint256 value);

    // @dev Returns the value of tokens in existence.
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    // @dev Returns the value of tokens owned by `account`.
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    // @dev Moves amount of tokens, returns a success boolean.
    // Emits a {Transfer} event.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    // @dev Returns the remaining allowed spending on behalf of `owner`
    // This value changes when {approve} or {transferFrom} are called.
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    // @dev Sets a allowance of `spender`. Returns a success boolean.
    // IMPORTANT: Beware that changing an allowance with this method brings the
    // risk of race condition for both the old and the new allowance use.
    // (reduce the old first?)
    // Emits an {Approval} event.
    function approve(address spender, uint256 value) external returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    // @dev Moves a tokens using the allowance mechanism.
    // Emits a {Transfer} event.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= value, "transfer exceeds allowance");

        _allowances[from][msg.sender] = currentAllowance - value;
        _transfer(from, to, value);
        return true;
    }

    // Internal functions

    function _mint(address _to, uint256 _amount) internal {
        require(_to != address(0), "mint to zero address");

        _totalSupply += _amount;
        _balances[_to] += _amount;

        emit Transfer(address(0), _to, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "burn from zero address");
        require(_balances[_account] >= _amount, "burn exceeds balance");

        _balances[_account] -= _amount;
        _totalSupply -= _amount;

        emit Transfer(_account, address(0), _amount);
    }

    function _transfer(address _from, address _to, uint256 amount) internal {
        require(_from != address(0), "transfer from zero address");
        require(_to != address(0), "transfer to zero address");
        require(_balances[_from] >= amount, "insufficient balance");

        _balances[_from] -= amount;
        _balances[_to] += amount;

        emit Transfer(_from, _to, amount);
    }

}
