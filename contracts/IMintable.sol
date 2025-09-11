// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMintable {
    /// @dev Issues the generated `amount` of tokens from address(0) to the `account`
    function mint(address account, uint256 amount) external;
}
