// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IChargeable {
    event FeesBurned(uint256 amount);

    /// @dev Burns accumulated fee tokens
    /// Emits a {FeesBurned} event.
    function burnFees() external;
}
