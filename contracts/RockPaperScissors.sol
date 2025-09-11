// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Rock-Paper-Scissors Duel Contract using IERC20 funds
/// @author
/// @notice A two-player commit-reveal Rock-Paper-Scissors game with IERC20-compatible stakes
/// @dev Players commit to a move hash, reveal later with move and salt. 
///      If both reveal, winner takes pot.
///      On timeout, the winner is awarded, tie is refunded.
///      The challenger is penalised for inactivity by defender's ability to claim the pot.
contract RockPaperScissors is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Move {
        None,
        Rock,
        Paper,
        Scissors
    }

    struct Duel {
        address challenger;
        address defender;
        uint256 stake;
        bytes32 challengerCommit;
        bytes32 defenderCommit;
        Move challengerMove;
        Move defenderMove;
        bool challengerRevealed;
        bool defenderRevealed;
        uint256 acceptTimestamp;
        bool accepted;
        bool resolved;
    }

    IERC20 private immutable _token;

    uint256 private _revealTimeout;

    mapping(uint256 => Duel) private _duels;
    uint256 private _duelCount;

    event DuelCreated(
        uint256 indexed duelId,
        address indexed challenger,
        address indexed defender,
        uint256 stake,
        bytes32 challengerCommit
    );

    event DuelAccepted(
        uint256 indexed duelId,
        address indexed defender,
        bytes32 defenderCommit
    );

    event MoveRevealed(
        uint256 indexed duelId,
        address indexed who,
        Move move
    );

    event DuelResolved(
        uint256 indexed duelId,
        address winner,
        uint256 reward
    );

    event DuelRefunded(
        uint256 indexed duelId
    );

    /// @param token The IERC20 staking token
    /// @param revealTimeout Duel timeout in seconds
    constructor(IERC20 token, uint256 revealTimeout) {
        _token = token;
        _revealTimeout = revealTimeout;
    }

    /// @notice Start a new duel by challenging another player
    /// @dev The challenger commits their move as a keccak256 hash of (uint8 move, salt).
    ///      Emits DuelCreated.
    /// @param defender The opponent's address
    /// @param stake The token stake (must be approved to this contract before calling)
    /// @param challengerCommit The commitment hash of the challenger's move
    /// @return duelId The ID the duel
    function challengeDuel(address defender, uint256 stake, bytes32 challengerCommit)
        external
        nonReentrant
        returns(uint256 duelId)
    {
        require(defender != address(0), "invalid defender");
        require(defender != msg.sender, "cannot play yourself");
        require(stake != 0, "empty stake");

        _token.safeTransferFrom(msg.sender, address(this), stake);

        ++_duelCount;
        duelId = _duelCount;
        _duels[duelId] = Duel({
            challenger: msg.sender,
            defender: defender,
            stake: stake,
            challengerCommit: challengerCommit,
            defenderCommit: bytes32(0),
            challengerMove: Move.None,
            defenderMove: Move.None,
            challengerRevealed: false,
            defenderRevealed: false,
            acceptTimestamp: 0,
            accepted: false,
            resolved: false
        });

        emit DuelCreated(duelId, msg.sender, defender, stake, challengerCommit);
    }

    /// @notice Accept a duel by committing to a move
    /// @param id The ID of the duel
    /// @param defenderCommit The commitment hash of the defender's move
    function acceptDuel(uint256 id, bytes32 defenderCommit) external nonReentrant {
        Duel storage duel = _duels[id];
        require(duel.challenger != address(0), "duel does not exist");
        require(!duel.accepted, "duel is already accepted");
        require(msg.sender == duel.defender, "not a defender");

        _token.safeTransferFrom(msg.sender, address(this), duel.stake);

        duel.defenderCommit = defenderCommit;
        duel.accepted = true;
        duel.acceptTimestamp = block.timestamp;

        emit DuelAccepted(id, msg.sender, defenderCommit);
    }

    /// @notice Reveal a previously committed move
    /// @dev Move uint8 encoding: 1 = Rock, 2 = Paper, 3 = Scissors and a salt (bytes32).
    ///      Must supply same salt as used in commitment.
    ///      The contract checks keccak256(abi.encodePacked(uint8(move), salt)) == storedCommit.
    /// @param id The ID of the duel
    /// @param moveUint The move as uint8 (1-3)
    /// @param salt The secret salt used in commitment
    function reveal(uint256 id, uint8 moveUint, bytes32 salt) external nonReentrant {
        Duel storage duel = _duels[id];
        require(duel.accepted, "not yet accepted");
        require(!duel.resolved, "is already resolved");

        Move move = _toMove(moveUint);

        // endcode without padding
        bytes32 computed = keccak256(abi.encodePacked(moveUint, salt));

        if (msg.sender == duel.challenger) {
            require(!duel.challengerRevealed, "the challenger already revealed");
            require(computed == duel.challengerCommit, "the reveal is invalid");
            duel.challengerMove = move;
            duel.challengerRevealed = true;
            emit MoveRevealed(id, msg.sender, move);
        } else if (msg.sender == duel.defender) {
            require(!duel.defenderRevealed, "the defender already revealed");
            require(computed == duel.defenderCommit, "the reveal is invalid");
            duel.defenderMove = move;
            duel.defenderRevealed = true;
            emit MoveRevealed(id, msg.sender, move);
        } else {
            revert("not a participant");
        }

        if (duel.challengerRevealed && duel.defenderRevealed) {
            _resolve(id);
        }
    }

    /// @notice Claim victory or refund after a duel times out
    ///         If the challenger doesn't reveal, the defender could claim the stake.
    ///         If neither actor reveals or only the challenger reveals, the stake is refunded.
    /// @dev If only defender revealed -> defender wins. Otherwise -> refund both.
    /// @param id The ID of the duel
    function claimTimeout(uint256 id) external nonReentrant {
        Duel storage duel = _duels[id];
        require(duel.accepted && !duel.resolved, "inactive duel");
        require(block.timestamp > duel.acceptTimestamp + _revealTimeout, "duel ended");

        // // Possible case: challenger revealed, but defender did not
        // if (d.challengerRevealed && !d.defenderRevealed) {
        //   _payout(d.challenger, d.stake * 2);
        //   emit DuelResolved(duelId, d.challenger, d.stake * 2);
        // }

        if (!duel.challengerRevealed && duel.defenderRevealed) {
            _payout(duel.defender, duel.stake * 2);
            emit DuelResolved(id, duel.defender, duel.stake * 2);
        } else {
            _token.safeTransfer(duel.challenger, duel.stake);
            _token.safeTransfer(duel.defender, duel.stake);
            emit DuelRefunded(id);
        }

        duel.resolved = true;
    }

    /// @dev Resolve duel when both players have revealed
    /// @param id The ID of the duel
    function _resolve(uint256 id) internal {
        Duel storage duel = _duels[id];
        require(!duel.resolved, "already resolved");

        uint256 pot = duel.stake * 2;

        if (duel.challengerMove == duel.defenderMove) {
            _token.safeTransfer(duel.challenger, duel.stake);
            _token.safeTransfer(duel.defender, duel.stake);
            emit DuelRefunded(id);
        } else if (_beats(duel.challengerMove, duel.defenderMove)) {
            _payout(duel.challenger, pot);
            emit DuelResolved(id, duel.challenger, pot);
        } else {
            _payout(duel.defender, pot);
            emit DuelResolved(id, duel.defender, pot);
        }

        duel.resolved = true;
    }

    /// @dev Internal token payout helper
    /// @param to Recipient address
    /// @param amount Token amount to transfer
    function _payout(address to, uint256 amount) internal {
        _token.safeTransfer(to, amount);
    }

    /// @param a First move
    /// @param b Second move
    /// @return A boolean that determines whether move `a` beats move `b`
    function _beats(Move a, Move b) internal pure returns (bool) {
        if (a == Move.Rock && b == Move.Scissors) return true;
        if (a == Move.Paper && b == Move.Rock) return true;
        if (a == Move.Scissors && b == Move.Paper) return true;
        return false;
    }

    /// @dev Convert uint8 into Move enum
    /// @param move Encoded move (1 = Rock, 2 = Paper, 3 = Scissors)
    /// @return The Move enum
    function _toMove(uint8 move) internal pure returns (Move) {
        require(move >= 1 && move <= 3, "invalid move");
        if (move == 1) return Move.Rock;
        if (move == 2) return Move.Paper;
        return Move.Scissors;
    }

}
