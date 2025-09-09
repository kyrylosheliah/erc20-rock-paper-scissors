import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("RockPaperScissorsModule", (m) => {
  const token = m.contract("RPSToken", ["Rock Paper Scissors Token", "RPS"]);

  // [address, revealDurationSeconds]
  const rps = m.contract("RockPaperScissors", [token, 60]);

  return { token, rps };
});
