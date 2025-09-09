// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./RPSToken.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract RockPaperScissors is ReentrancyGuard {
  using SafeERC20 for RPSToken;

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

  RPSToken public immutable token;
  uint256 public revealTimeout;

  mapping(uint256 => Duel) public duels;
  uint256 duelCount;

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

  constructor(RPSToken _token, uint256 _revealTimeout) {
    token = _token;
    revealTimeout = _revealTimeout;
  }

  function challengeDuel(
    address _defender,
    uint256 _stake,
    bytes32 _challengerCommit
  ) external nonReentrant returns(uint256 duelId) {
    require(_defender != address(0), "invalid defender");
    require(_defender != msg.sender, "cannot play yourself");
    require(_stake != 0, "empty stake");

    token.safeTransferFrom(msg.sender, address(this), _stake);

    ++duelCount;
    duelId = duelCount;
    duels[duelId] = Duel({
      challenger: msg.sender,
      defender: _defender,
      stake: _stake,
      challengerCommit: _challengerCommit,
      defenderCommit: bytes32(0),
      challengerMove: Move.None,
      defenderMove: Move.None,
      challengerRevealed: false,
      defenderRevealed: false,
      acceptTimestamp: 0,
      accepted: false,
      resolved: false
    });

    emit DuelCreated(duelId, msg.sender, _defender, _stake, _challengerCommit);
  }

  function acceptDuel(uint256 _id, bytes32 _defenderCommit) external nonReentrant {
    Duel storage duel = duels[_id];
    require(duel.challenger != address(0), "duel does not exist");
    require(!duel.accepted, "duel is already accepted");
    require(msg.sender == duel.defender, "not a defender");

    token.safeTransferFrom(msg.sender, address(this), duel.stake);

    duel.defenderCommit = _defenderCommit;
    duel.accepted = true;
    duel.acceptTimestamp = block.timestamp;

    emit DuelAccepted(_id, msg.sender, _defenderCommit);
  }

  /// @notice Move is encoded as uint8 (1=Rock,2=Paper,3=Scissors) and a salt (bytes32).
  /// The contract checks keccak256(abi.encodePacked(uint8(move), salt)) == storedCommit.
  function reveal(uint256 _id, uint8 _moveUint, bytes32 _salt) external nonReentrant {
    Duel storage duel = duels[_id];
    require(duel.accepted, "not yet accepted");
    require(!duel.resolved, "is already resolved");

    Move move = _toMove(_moveUint);

    // endcode without padding
    bytes32 computed = keccak256(abi.encodePacked(_moveUint, _salt));

    if (msg.sender == duel.challenger) {
      require(!duel.challengerRevealed, "the challenger already revealed");
      require(computed == duel.challengerCommit, "the reveal is invalid");
      duel.challengerMove = move;
      duel.challengerRevealed = true;
      emit MoveRevealed(_id, msg.sender, move);
    } else if (msg.sender == duel.defender) {
      require(!duel.defenderRevealed, "the defender already revealed");
      require(computed == duel.defenderCommit, "the reveal is invalid");
      duel.defenderMove = move;
      duel.defenderRevealed = true;
      emit MoveRevealed(_id, msg.sender, move);
    } else {
      revert("not a participant");
    }

    if (duel.challengerRevealed && duel.defenderRevealed) {
      _resolve(_id);
    }
  }

    /// @notice If the challenger doesn't reveal, the defender could claim the stake.
    /// @notice If neither actor reveals or only the challenger reveals, the stake is refunded.
    function claimTimeout(uint256 _id) external nonReentrant {
      Duel storage duel = duels[_id];
      require(duel.accepted && !duel.resolved, "inactive duel");
      require(block.timestamp > duel.acceptTimestamp + revealTimeout, "duel ended");

      // // Possible case: challenger revealed, but defender did not
      // if (d.challengerRevealed && !d.defenderRevealed) {
      //   _payout(d.challenger, d.stake * 2);
      //   emit DuelResolved(duelId, d.challenger, d.stake * 2);
      // }

      if (!duel.challengerRevealed && duel.defenderRevealed) {
        _payout(duel.defender, duel.stake * 2);
        emit DuelResolved(_id, duel.defender, duel.stake * 2);
      } else {
        token.safeTransfer(duel.challenger, duel.stake);
        token.safeTransfer(duel.defender, duel.stake);
        emit DuelRefunded(_id);
      }

      duel.resolved = true;
    }

    function _resolve(uint256 _id) internal {
      Duel storage duel = duels[_id];
      require(!duel.resolved, "already resolved");

      uint256 pot = duel.stake * 2;

      if (duel.challengerMove == duel.defenderMove) {
        token.safeTransfer(duel.challenger, duel.stake);
        token.safeTransfer(duel.defender, duel.stake);
        emit DuelRefunded(_id);
      } else if (_beats(duel.challengerMove, duel.defenderMove)) {
        _payout(duel.challenger, pot);
        emit DuelResolved(_id, duel.challenger, pot);
      } else {
        _payout(duel.defender, pot);
        emit DuelResolved(_id, duel.defender, pot);
      }

      duel.resolved = true;
    }

    function _payout(address _to, uint256 _amount) internal {
      token.safeTransfer(_to, _amount);
    }

    function _beats(Move _a, Move _b) internal pure returns (bool) {
      if (_a == Move.Rock && _b == Move.Scissors) return true;
      if (_a == Move.Paper && _b == Move.Rock) return true;
      if (_a == Move.Scissors && _b == Move.Paper) return true;
      return false;
    }

    function _toMove(uint8 _move) internal pure returns (Move) {
      require(_move >= 1 && _move <= 3, "invalid move");
      if (_move == 1) return Move.Rock;
      if (_move == 2) return Move.Paper;
      return Move.Scissors;
    }

}
