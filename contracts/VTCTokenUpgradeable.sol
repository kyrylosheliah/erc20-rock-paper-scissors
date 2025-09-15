// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./ERC20TokenUpgradeable.sol";
import "./interfaces/IVoteable.sol";
import "./interfaces/ITradeable.sol";
import "./interfaces/IChargeable.sol";

/// @title VTC: Voteable Tradeable Chargeable Token
/// @author
/// @notice Implements IERC20, IBurnable, IMintable, IVoteable, IChargeable, ITradeable. Some methods are
/// role-restricted. Trade burns fees.
/// @dev Implementation notes:
/// - Start voting threshold: 0.1% of `totalSupply`
/// - Voting threshold to cast a vote: 0.05% of `totalSupply`
/// - Votes are weighted by `balances[voter]`
/// - Transfers / buy / sell are forbidden for addresses that have voted in the current round.
contract VTCTokenUpgradeable is Initializable, ERC20TokenUpgradeable, IVoteable, ITradeable, IChargeable {
    // ---------------
    // IVoteable state
    // ---------------

    mapping(uint256 => mapping(address => bool)) votingRoundParticipation;

    mapping(uint256 => mapping(uint256 => uint256)) votingRoundOptionWeights;

    uint256 public votingWinnerWeight;

    uint256 public votingWinnerPrice;

    uint256 public currentVotingRoundId;

    uint256 public votingTimestamp;

    bool public votingActive;

    uint256 public votingTimeoutSeconds;

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
    uint256 public buyingFeeBasePoints;

    /// @notice A basis point (in 0.01 percents)
    uint256 public sellingFeeBasePoints;

    // -----------
    // constructor
    // -----------

    /// @param name_ The name of the token (e.g., "Rock Paper Scissors Token")
    /// @param symbol_ The symbol of the token (e.g., "RPS")
    /// @param votingTimeoutSeconds_ Seconds until price voting deactivates
    function VTCTokenInitialize(string memory name_, string memory symbol_, uint256 votingTimeoutSeconds_)
        public
        initializer
    {
        __VTCToken__init(name_, symbol_, votingTimeoutSeconds_);
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
    function transfer(address to, uint256 value) public override returns (bool) {
        if (votingActive) {
            if (votingRoundParticipation[currentVotingRoundId][msg.sender]) {
                revert VotingParticipation(msg.sender);
            } else if (votingRoundParticipation[currentVotingRoundId][to]) {
                revert VotingParticipation(to);
            }
        }
        return super.transfer(to, value);
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (votingActive) {
            if (votingRoundParticipation[currentVotingRoundId][from]) {
                revert VotingParticipation(from);
            } else if (votingRoundParticipation[currentVotingRoundId][to]) {
                revert VotingParticipation(to);
            }
        }
        return super.transferFrom(from, to, value);
    }

    // -------------------
    // IVoteable functions
    // -------------------

    /// @notice Start a new voting with an initial `price`.
    /// @dev Voter is deemed eligible to start by holding at least 0.1% of the token supply.
    /// @param price Price in wei per token units (10**decimals) of token unit per TOKEN.
    function startVoting(uint256 price) external {
        if (votingActive) {
            revert VotingActive();
        }

        uint256 threshold = totalSupply / 1000; // 0.1% is 0.001
        if (balances[msg.sender] < threshold) {
            revert InsufficientVotingBalance(threshold);
        }

        votingWinnerWeight = 0;
        votingWinnerPrice = 0;
        votingTimestamp = block.timestamp;
        ++currentVotingRoundId;
        votingActive = true;

        _castVote(msg.sender, price);

        emit VotingStarted(msg.sender, votingTimestamp, currentVotingRoundId);
    }

    /// @notice Vote in the current round
    /// @dev Voter is deemed eligible to vote by holding at least 0.05% of the token supply.
    /// Voting is available once per round and blocks the trade interface.
    /// @param price Price in wei per token units (10**decimals of token unit per TOKEN)
    function vote(uint256 price) external {
        if (!votingActive) {
            revert VotingInactive();
        } else if (votingRoundParticipation[currentVotingRoundId][msg.sender]) {
            revert AlreadyVoted();
        }

        uint256 threshold = totalSupply / 2000; // 0.05% is 0.0005
        if (balances[msg.sender] < threshold) {
            revert InsufficientVotingBalance(threshold);
        }

        _castVote(msg.sender, price);
    }

    /// @notice End the round and pick the price.
    /// @dev Can be called by anyone after `votingTimeoutSeconds` seconds since `votingTimestamp`.
    /// Emits a {VotingEnded} event with the selected price and total weight.
    function endVoting() external {
        if (!votingActive) {
            revert VotingInactive();
        } else if (block.timestamp < votingTimestamp + votingTimeoutSeconds) {
            revert VotingNotExpired(votingTimestamp + votingTimeoutSeconds);
        }

        uint256 winnerWeight = votingWinnerWeight;
        uint256 winnerPrice = votingWinnerPrice;

        currentPrice = winnerPrice;

        votingActive = false;

        emit VotingEnded(winnerPrice, winnerWeight, currentVotingRoundId);
    }

    // ---------------------
    // IChargeable functions
    // ---------------------

    /// @notice Burn accumulated fee tokens.
    /// Emits a {FeesBurned} event.
    function burnFees() external onlyAdmins {
        if (block.timestamp < feeBurnTimestamp + 7 days) {
            revert BurningCooldown(feeBurnTimestamp + 7 days);
        }

        uint256 feeBalance_ = feeBalance;
        if (feeBalance_ == 0) {
            revert ZeroBurningBalance();
        }

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
    /// @param buyingFeeBasePoints_ Buying fee in basis points (0.01% per point)
    /// @param sellingFeeBasePoints_ Selling fee in basis points (0.01% per point)
    function setTradeFees(uint256 buyingFeeBasePoints_, uint256 sellingFeeBasePoints_) external onlyAdmins {
        buyingFeeBasePoints = buyingFeeBasePoints_;
        sellingFeeBasePoints = sellingFeeBasePoints_;
        emit TradeFeesUpdated(buyingFeeBasePoints_, sellingFeeBasePoints_);
    }

    /// @notice Buy tokens with attached ETH.
    /// Voters cannot be buyers to prevent balance-weighted insider trading.
    /// Emits a {Bought} event.
    /// @dev `currentPrice` is in wei per token unit (10**decimals of token unit per TOKEN)
    function buy() external payable {
        if (votingActive) {
            if (votingRoundParticipation[currentVotingRoundId][msg.sender]) {
                revert VotingParticipation(msg.sender);
            }
        }
        if (msg.value == 0) {
            revert ZeroETHPayment();
        }
        if (currentPrice == 0) {
            revert PriceNotSet();
        }

        // wei/eth: 10**18
        // - suppose price or wei/tokenUnit is 10**14
        //   then per 1 wei of ETHEREUM sold you get 10**4 or 10_000 token units of TOKEN
        // - suppose price or wei/tokenUnit is 10**22
        //   then per 10**4 or 10_000 wei of ETHEREUM sold you get 1 token unit of TOKEN
        uint256 tokens = (msg.value * (10 ** decimals)) / currentPrice;
        uint256 fee = (tokens * buyingFeeBasePoints) / 10000;
        uint256 tokenPurchasedAmount = tokens - fee;

        _mint(msg.sender, tokenPurchasedAmount);
        if (fee > 0) {
            _mint(address(this), fee);
            feeBalance += fee;
        }

        emit Bought(msg.sender, msg.value, tokenPurchasedAmount);
    }

    /// @notice Sell `amount` of tokens for ETH from the contract balance.
    /// Voters cannot be sellers to prevent balance-weighted insider trading.
    /// Emits a {Sold} event.
    /// @param amount is in wei per token unit (10**decimals of token unit per TOKEN)
    function sell(uint256 amount) external {
        if (votingActive) {
            if (votingRoundParticipation[currentVotingRoundId][msg.sender]) {
                revert VotingParticipation(msg.sender);
            }
        }
        if (amount == 0) {
            revert ZeroTokenPayment();
        }
        if (currentPrice == 0) {
            revert PriceNotSet();
        }

        _burn(msg.sender, amount);
        uint256 fee = (amount * sellingFeeBasePoints) / 10000;
        uint256 tokenSoldAmount = amount - fee;
        if (fee > 0) {
            _mint(address(this), fee);
            feeBalance += fee;
        }

        // wei/eth: 10**18
        // - suppose price or wei/tokenUnit is 10**14
        //   then per [10**4 or 10_000] token units of TOKEN sold you get 1 wei of ETHEREUM
        // - suppose price or wei/tokenUnit is 10**22
        //   then per 1 token unit of TOKEN sold you get [10**4 or 10_000] wei of ETHEREUM
        uint256 ethAmount = (tokenSoldAmount * currentPrice) / (10 ** decimals);
        if (address(this).balance < ethAmount) {
            revert InsufficientETHTradeBalance();
        }

        payable(msg.sender).transfer(ethAmount);

        emit Sold(msg.sender, amount, ethAmount);
    }

    // ------------------
    // Internal functions
    // ------------------

    function __VTCToken__init(string memory name_, string memory symbol_, uint256 votingTimeoutSeconds_) internal {
        __AccessControl_init();
        __ERC20Token_init(name_, symbol_);

        votingTimeoutSeconds = votingTimeoutSeconds_;
        feeBurnTimestamp = block.timestamp;
    }

    /// @dev Records a vote in the current round.
    function _castVote(address voter, uint256 price) internal {
        votingRoundParticipation[currentVotingRoundId][voter] = true;

        uint256 weight = balances[voter];
        uint256 newWeight = votingRoundOptionWeights[currentVotingRoundId][price] + weight;
        votingRoundOptionWeights[currentVotingRoundId][price] = newWeight;

        if (newWeight > votingWinnerWeight) {
            votingWinnerWeight = newWeight;
            votingWinnerPrice = price;
        }

        emit Voted(voter, price, weight, currentVotingRoundId);
    }
}
