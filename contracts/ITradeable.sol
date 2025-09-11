// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ITradeable {
    event TradeFeesUpdated(uint256 buyBP, uint256 sellBP);

    event Bought(address indexed buyer, uint256 ethPaid, uint256 tokensMinted);

    event Sold(address indexed seller, uint256 tokensBurned, uint256 ethReturned);

    /// @dev Sets fees basis points
    /// Emits a {FeesUpdated} event
    function setTradeFees(uint256 buyBP, uint256 sellBP) external;

    /// @dev Buy tokens with attached ETH
    function buy() external payable;

    /// @dev Sell `amount` of tokens for ETH from the contract balance
    function sell(uint256 amount) external;
}
