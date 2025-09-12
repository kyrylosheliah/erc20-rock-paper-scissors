// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IVoteable {
    event VotingStarted(address indexed starter, uint256 startTime, uint256 roundId);

    event Voted(address indexed voter, uint256 price, uint256 weight, uint256 roundId);

    event VotingEnded(uint256 winningPrice, uint256 totalWeight, uint256 roundId);

    /// @notice Start a new voting with an initial `price`
    function startVoting(uint256 price) external;

    /// @notice Vote in the current round
    function vote(uint256 price) external;

    /// @notice End the round and pick the price
    function endVoting() external;
}
