// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./ERC20Token.sol";
import "./IVoteable.sol";
import "./ITradeable.sol";
import "./IChargeable.sol";

/// @title VoteableTradeableChargeableToken
/// @author
/// @notice Implements IERC20, IBurnable, IMintable, IVoteable, IChargeable, ITradeable. Some methods are
/// role-restricted. Trade burns fees.
/// @dev Implementation notes:
/// - Start voting threshold: 0.1% of `totalSupply`
/// - Voting threshold to cast a vote: 0.05% of `totalSupply`
/// - Votes are weighted by `balances[voter]`
/// - Transfers / buy / sell are forbidden for addresses that have voted in current round.
contract VoteableTradeableChargeableToken is ERC20Token, IVoteable, ITradeable, IChargeable {

    // ---------------
    // IVoteable types
    // ---------------

    struct VotingPrice {
        uint256 roundId;
        uint256 weight;
    }

    // ---------------
    // IVoteable state
    // ---------------

    /// @notice `accountAddress` to `roundId`
    mapping(address => uint256) public votes;

    /// @notice `priceValue` to {VotingPrice}
    mapping(uint256 => VotingPrice) public prices;

    uint256 public votingPriceWinnerWeight;

    uint256 public votingPriceWinner;

    uint256 public votingRoundId;

    uint256 public votingTimestamp;

    bool public votingActive;

    uint256 public votingTimeoutSeconds;

    uint256 public votingHistorySize;

    uint256 public currentPrice;

    // -----------------
    // IChargeable state
    // -----------------

    uint256 public feeBalance;

    uint256 public feeBurnTimestamp;

    // ----------------
    // ITradeable state
    // ----------------

    /// @notice A basis point (in 0.01 percents)
    uint256 public buyingFeeBP;

    /// @notice A basis point (in 0.01 percents)
    uint256 public sellingFeeBP;

    // -------------------
    // IVoteable modifiers
    // -------------------

    /// @dev Modifier to revert if `msg.sender` voted in the current round
    modifier voteEmpty(address voter, string memory message) {
        if (votingActive) {
            bool voted = votes[voter] == votingRoundId;
            require(!voted, message);
        }
        _;
    }

    // -----------
    // constructor
    // -----------

    /// @param name_ The name of the token (e.g., "Rock Paper Scissors Token")
    /// @param symbol_ The symbol of the token (e.g., "RPS")
    constructor(string memory name_, string memory symbol_, uint256 votingTimeoutSeconds_, uint256 votingHistorySize_)
        ERC20Token(name_, symbol_)
    {
        votingTimeoutSeconds = votingTimeoutSeconds_;
        votingHistorySize = votingHistorySize_;
        feeBurnTimestamp = block.timestamp;
    }

    // ------------------
    // fallback functions
    // ------------------

    /// @notice Plain ETH transfers fallback
    receive() external payable {}

    // --------------------
    // ERC20Token overrides
    // --------------------

    /// @inheritdoc IERC20
    function transfer(address to, uint256 value)
        public
        override
        voteEmpty(msg.sender, "sender voted")
        voteEmpty(to, "recipient voted")
        returns (bool)
    {
        return super.transfer(to, value);
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 value)
        public
        override
        voteEmpty(from, "issuer voted")
        voteEmpty(to, "recipient voted")
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }

    // -------------------
    // IVoteable functions
    // -------------------

    /// @notice Start a new voting with an initial `price`.
    /// @dev Voter is deemed eligible to start by holding at least 0.1% of the token supply.
    /// @param price Price in wei per token units (10**decimals).
    function startVoting(uint256 price) external {
        require(!votingActive, "voting is already active");

        uint256 threshold = totalSupply / 1000;
        require(balances[msg.sender] >= threshold, "not enough tokens");

        votingPriceWinnerWeight = 0;
        votingPriceWinner = 0;
        votingTimestamp = block.timestamp;
        ++votingRoundId;
        votingActive = true;

        _castVote(msg.sender, price);

        emit VotingStarted(msg.sender, votingTimestamp, votingRoundId);
    }

    /// @notice Vote in the current round
    /// @dev Voter is deemed eligible to vote by holding at least 0.05% of the token supply.
    /// Voting is available once per round and blocks the trade interface.
    /// @param price Price in wei per token units (10**decimals)
    function vote(uint256 price) external voteEmpty(msg.sender, "already voted") {
        require(votingActive, "no voting");

        uint256 threshold = totalSupply / 2000;
        require(balances[msg.sender] >= threshold, "not enough tokens");

        _castVote(msg.sender, price);
    }

    /// @notice End the round and pick the price.
    /// @dev Can be called by anyone after `votingTimeoutSeconds` seconds since `votingTimestamp`.
    /// Emits a {VotingEnded} event with the selected price and total weight.
    function endVoting() external {
        require(votingActive, "voting is not active");
        require(block.timestamp >= votingTimestamp + votingTimeoutSeconds, "voting did not time out");

        uint256 winnerWeight = votingPriceWinnerWeight;
        uint256 winnerPrice = votingPriceWinner;

        currentPrice = winnerPrice;

        votingActive = false;

        emit VotingEnded(winnerPrice, winnerWeight, votingRoundId);
    }

    // ---------------------
    // IChargeable functions
    // ---------------------

    /// @notice Burn accumulated fee tokens.
    /// Emits a {FeesBurned} event.
    function burnFees() external onlyAdmins {
        require(block.timestamp >= feeBurnTimestamp + 7 days, "can burn only once per 7 days");

        uint256 feeBalance_ = feeBalance;
        require(feeBalance_ > 0, "fee pool is 0");

        feeBalance = 0;
        _burn(address(this), feeBalance_);
        feeBurnTimestamp = block.timestamp;

        emit FeesBurned(feeBalance_);
    }

    // --------------------
    // ITradeable functions
    // --------------------

    /// @notice Set fee basis points.
    /// Emits a {TradeFeesUpdated}.
    /// @param buyingFeeBP_ Buy fee basis points
    /// @param sellingFeeBP_ Sell fee sell basis points
    function setTradeFees(uint256 buyingFeeBP_, uint256 sellingFeeBP_) external onlyAdmins {
        buyingFeeBP = buyingFeeBP_;
        sellingFeeBP = sellingFeeBP_;
        emit TradeFeesUpdated(buyingFeeBP_, sellingFeeBP_);
    }

    /// @notice Buy tokens with attached ETH.
    /// Voters cannot be buyers to prevent balance-weighted insider trading.
    /// Emits a {Bought} event.
    /// @dev `currentPrice` is in wei per token unit (10**decimals)
    function buy() external payable voteEmpty(msg.sender, "sender voted") {
        require(msg.value > 0, "insufficient payment");
        require(currentPrice > 0, "price not set");

        uint256 tokens = (msg.value * (10 ** decimals)) / currentPrice;
        uint256 fee = (tokens * buyingFeeBP) / 10000;
        uint256 net = tokens - fee;

        _mint(msg.sender, net);
        if (fee > 0) {
            _mint(address(this), fee);
            feeBalance += fee;
        }

        emit Bought(msg.sender, msg.value, net);
    }

    /// @notice Sell `amount` of tokens for ETH from the contract balance.
    /// Voters cannot be sellers to prevent balance-weighted insider trading.
    /// Emits a {Sold} event.
    /// @param amount is in wei per token unit (10**decimals)
    function sell(uint256 amount) external voteEmpty(msg.sender, "sender voted") {
        require(amount > 0, "zero amount");
        require(currentPrice > 0, "price not set");

        _burn(msg.sender, amount);
        uint256 fee = (amount * sellingFeeBP) / 10000;
        uint256 net = amount - fee;
        if (fee > 0) {
            _mint(address(this), fee);
            feeBalance += fee;
        }

        uint256 ethAmount = (net * currentPrice) / (10 ** decimals);
        require(address(this).balance >= ethAmount, "insufficient ETH");

        payable(msg.sender).transfer(ethAmount);

        emit Sold(msg.sender, amount, ethAmount);
    }

    // ------------------
    // Internal functions
    // ------------------

    /// @dev Records a vote in the current round.
    function _castVote(address voter, uint256 price) internal {
        uint256 weight = balances[voter];

        votes[voter] = votingRoundId;

        if (prices[price].roundId != votingRoundId) {
            prices[price].weight = weight; // 0 + weight
            prices[price].roundId = votingRoundId;
        } else {
            prices[price].weight += weight;
        }

        uint256 accumulatedWeight = prices[price].weight;

        if (accumulatedWeight > votingPriceWinnerWeight) {
            votingPriceWinnerWeight = accumulatedWeight;
            votingPriceWinner = price;
        }

        emit Voted(voter, price, weight, votingRoundId);
    }
}
