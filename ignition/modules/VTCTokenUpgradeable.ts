// TODO: deployment code

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import type { UpgradeableProxy } from "../../types/ethers-contracts/UpgradeableProxy.ts";

export default buildModule("VTCTokenUpgradeable", (m) => {
  const token = m.contract("VTCTokenUpgradeable", ["Votable Tradeable Chargeable Token", "VTC"]);

  // new UpgradeableProxy(address(token), msg.sender, abi.encodeWithSignature(
  //     "initialize(string,string,uint256,uint256)",
  //     "Rock Paper Scissors Token", "RPS", 3600, 10
  // ));

  // const proxy: UpgradeableProxy = m.contract("UpgradeableProxy", [token, 60]);

  return { token, rps };
});
