// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./ERC20TokenUpgradeable.sol";

contract ERC20Token is ERC20TokenUpgradeable {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        ERC20TokenInitialize(name_, symbol_, decimals_);
    }
}
