// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/VTCTokenUpgradeable.sol";
import "../contracts/VTCTokenUpgradeableDestroyer.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract VTCTokenUpgradeableDeployTest is Test {
    VTCTokenUpgradeable public token;
    ERC1967Proxy public proxy;

    function setUp() public {
        vm.startBroadcast();

        // logic contract
        VTCTokenUpgradeable logic = new VTCTokenUpgradeable();
        console.log("Logic contract deployed at:", address(logic));

        bytes memory data = abi.encodeWithSelector(
            VTCTokenUpgradeable.VTCTokenInitialize.selector,
            "Voteable Tradeable Chargeable Token",
            "VTC",
            18,
            60 // votingTimeoutSeconds
        );

        // UUPS proxy contract
        proxy = new ERC1967Proxy(address(logic), data);
        console.log("Proxy deployed at:", address(proxy));
        token = VTCTokenUpgradeable(payable(address(proxy)));

        // token.mint(msg.sender, 1000 ether);
        console.log("Deployer's initial balance:", token.balanceOf(msg.sender));
    }

    function testUpgrade() public {
        VTCTokenUpgradeable logicV2 = new VTCTokenUpgradeable();
        token.upgradeToAndCall(payable(address(logicV2)), bytes(""));

        console.log("balance of sender is ", token.balanceOf(msg.sender));
        token.mint(msg.sender, 1500 ether);
        console.log("balance of sender after minting is ", token.balanceOf(msg.sender));
        assert(token.balanceOf(msg.sender) == 1500 ether);
    }

    function testDestructiveUpgrade() public {
        VTCTokenUpgradeableDestroyer logicV3 = new VTCTokenUpgradeableDestroyer();
        token.upgradeToAndCall(payable(address(logicV3)), bytes(""));

        console.log("balance of sender is ", token.balanceOf(msg.sender));
        VTCTokenUpgradeableDestroyer(payable(address(proxy))).makeRich(msg.sender);
        console.log("balance of sender after making him rich is ", token.balanceOf(msg.sender));
        assert(token.balanceOf(msg.sender) == 0 ether);
    }

    function testRestorationUpgrade() public {
        VTCTokenUpgradeable logicV4 = new VTCTokenUpgradeable();
        token.upgradeToAndCall(payable(address(logicV4)), bytes(""));

        console.log("balance of sender is ", token.balanceOf(msg.sender));
        token.mint(msg.sender, 2000 ether);
        console.log("balance of sender after minting is ", token.balanceOf(msg.sender));
        assert(token.balanceOf(msg.sender) == 2000 ether);
    }
}
