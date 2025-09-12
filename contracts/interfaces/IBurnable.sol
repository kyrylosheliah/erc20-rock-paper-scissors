// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IBurnable {
    /// @dev Burns the specified amount of tokens
    function burn(uint256 amount) external;
}
