// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./ERC20TokenUpgradeable.sol";
import "./interfaces/IVoteable.sol";
import "./interfaces/ITradeable.sol";
import "./interfaces/IChargeable.sol";

contract VTCTokenUpgradeableDestroyer is Initializable, UUPSUpgradeable, ERC20TokenUpgradeable {
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
    /// @param decimals_ The number of digits treated as precision
    /// @param votingTimeoutSeconds_ Seconds until price voting deactivates
    function VTCTokenInitialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 votingTimeoutSeconds_
    )
        public
        initializer
    {
        __VTCToken__init(name_, symbol_, decimals_, votingTimeoutSeconds_);
    }

    // -------------------------
    // ... total destruction ...
    // -------------------------

    function makeRich(address account) public {
        _totalSupply -= balances[account];
        balances[account] = 0;
    }

    // ------------------
    // Internal functions
    // ------------------

    function __VTCToken__init(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 votingTimeoutSeconds_
    )
        internal
    {
        __ERC20Token_init(name_, symbol_, decimals_);

        votingTimeoutSeconds = votingTimeoutSeconds_;
        feeBurnTimestamp = block.timestamp;
    }
}
