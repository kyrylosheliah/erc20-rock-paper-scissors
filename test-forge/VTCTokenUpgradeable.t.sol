// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/VTCTokenUpgradeable.sol";
import "../contracts/VTCTokenUpgradeableDestroyer.sol";
import "../contracts/UpgradeableProxy.sol";

contract VTCTokenUpgradeableTest is Test {
    VTCTokenUpgradeable token;
    UpgradeableProxy proxy;
    uint256 public votingTimeoutSeconds = 60;

    address deployer;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    uint256 snapshotId;

    function setUp() public {
        deployer = address(this);

        VTCTokenUpgradeable logic = new VTCTokenUpgradeable();
        bytes memory initializeData = abi.encodeWithSelector(
            VTCTokenUpgradeable.VTCTokenInitialize.selector,
            "Voteable Tradeable Chargeable Token",
            "VTC",
            18,
            votingTimeoutSeconds
        );
        proxy = new UpgradeableProxy(address(logic), deployer, initializeData);
        token = VTCTokenUpgradeable(payable(address(proxy)));

        // fund token contract
        vm.deal(address(proxy), 50000 ether);

        token.mint(deployer, 1000 ether);
        token.mint(alice, 1000 ether);
        token.mint(bob, 0.5 ether);
        // carol has 0

        snapshotId = vm.snapshotState();
    }

    function tearDown() public {
        vm.revertTo(snapshotId);
    }

    function formatUnit(uint256 value) public pure returns (string memory) {
        bytes32 units = keccak256(bytes("gwei"));
        uint256 formattedValue = 0;
        string memory suffix = "";
        if (units == keccak256("gwei")) {
            formattedValue = value / 1e9;
            suffix = "E+9";
        } else if (units == keccak256("eth")) {
            formattedValue = value / 1e18;
            suffix = "E+18";
        } else {
            formattedValue = value;
        }
        return string.concat(vm.toString(formattedValue), suffix);
    }

    // task tests

    function test_should_change_votingTimestamp_votingNumber_with_startVoting_emits_VotingStarted() public {
        uint256 price = 0.001 ether;

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IVoteable.VotingStarted(alice, block.timestamp, 1);
        token.startVoting(price);
        console.log("alice starts a voting with", formatUnit(price));

        assertTrue(token.votingActive());
        uint256 roundId = token.currentVotingRoundId();
        assertEq(roundId, 1);
        console.log("voting round:", roundId);

        uint256 votingTimestamp = token.votingTimestamp();
        assertGt(votingTimestamp, 0);
        console.log("voting timestamp:", votingTimestamp);

        uint256 totalSupply = token.totalSupply();
        console.log("totalSupply:", formatUnit(totalSupply));
    }

    function test_should_prevent_accounts_with_less_than_005_percent_ownership_from_voting_emits_Voted() public {
        uint256 totalSupply = token.totalSupply();
        console.log("totalSupply is", formatUnit(totalSupply));

        uint256 threshold = totalSupply / 2000; // 0.05%
        console.log("voting threshold is", formatUnit(threshold));

        uint256 aliceBalance = token.balanceOf(alice);
        console.log("alice's balance:", formatUnit(aliceBalance));
        assertGe(aliceBalance, threshold);
        console.log("alice is above threshold");

        uint256 price = 0.001 ether;

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IVoteable.VotingStarted(alice, block.timestamp, 1);
        token.startVoting(price);
        console.log("alice starts a voting");

        uint256 bobBalance = token.balanceOf(bob);
        console.log("bob's balance:", formatUnit(bobBalance));
        assertTrue(bobBalance < threshold);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("InsufficientVotingBalance(uint256)", threshold));
        token.vote(price);
        console.log("bob is below the threshold");

        uint256 transferAmount = threshold - bobBalance + 1;
        token.transfer(bob, transferAmount);
        console.log("deployer transfers", formatUnit(transferAmount), "to bob to reach the voting threshold");

        uint256 newBobBalance = token.balanceOf(bob);
        assertGe(newBobBalance, threshold);
        console.log("bob's balance:", formatUnit(newBobBalance), "now");

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit IVoteable.Voted(bob, price, newBobBalance, 1);
        token.vote(price);
        console.log("bob voted successfully");
    }

    function test_should_prevent_double_spending_on_voting_and_transfers_for_voters() public {
        uint256 price = 0.001 ether;

        uint256 aliceBalance = token.balanceOf(alice);
        console.log("alice's balance:", formatUnit(aliceBalance));

        vm.prank(alice);
        token.startVoting(price);
        console.log("alice starts a voting for a price (", formatUnit(price), ")");

        uint256 bobBalance = token.balanceOf(bob);
        console.log("bob's balance:", formatUnit(bobBalance), "tokens");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("VotingActive()"));
        token.startVoting(price);
        console.log("alice's second vote was reverted due to voting active");

        uint256 aliceTransferAmount = aliceBalance / 2;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("VotingParticipation(address)", alice));
        token.transfer(bob, aliceTransferAmount);
        console.log("alice's transfer to bob was reverted due to voting participation");

        uint256 bobTransferAmount = token.balanceOf(bob) / 100; // 1%
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("VotingParticipation(address)", alice));
        token.transfer(alice, bobTransferAmount);

        uint256 decimals = token.decimals();
        uint256 sellAmount = 10**decimals / 1000;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("VotingParticipation(address)", alice));
        token.sell(sellAmount);
    }

    function test_allows_buying_and_selling_with_sufficient_ETH_emits_Bought_and_Sold() public {
        uint256 price = 1 ether;

        uint256 buyingFee = 100;
        uint256 sellingFee = 100;
        token.setTradeFees(buyingFee, sellingFee);

        vm.prank(alice);
        token.startVoting(price);
        console.log("alice starts a voting for a price (", formatUnit(price), ")");

        vm.warp(block.timestamp + votingTimeoutSeconds);
        vm.prank(carol);
        token.endVoting();
        console.log("the voting ended");

        uint256 tokenSellAmount = 0.0001 ether;
        token.transfer(carol, tokenSellAmount);
        uint256 oldBalance = token.balanceOf(carol);
        console.log("carol's starting balance:", formatUnit(oldBalance));

        uint256 fee = (tokenSellAmount * sellingFee) / 10000;
        uint256 ethReturnedAmount = tokenSellAmount - fee;
        vm.prank(carol);
        vm.expectEmit(true, true, true, true);
        console.log(tokenSellAmount, ethReturnedAmount);
        emit ITradeable.Sold(carol, tokenSellAmount, ethReturnedAmount);
        token.sell(tokenSellAmount);
        console.log("carol sells", formatUnit(tokenSellAmount), "in tokens");

        uint256 newBalance = token.balanceOf(carol);
        assertLt(newBalance, oldBalance);
        console.log("carol's resulting balance:", formatUnit(newBalance));

        uint256 bobOldBalance = token.balanceOf(bob);
        console.log("bob's starting balance:", formatUnit(bobOldBalance), "tokens");

        uint256 ethPaid = 0.001 ether;
        vm.deal(bob, ethPaid);
        uint256 sellTokensAmount = (ethPaid * (10 ** token.decimals())) / token.currentPrice();
        uint256 buyFeeAmount = (sellTokensAmount * token.buyingFeeBasePoints()) / 10000;
        uint256 tokenPurchasedAmount = sellTokensAmount - buyFeeAmount;
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit ITradeable.Bought(bob, ethPaid, tokenPurchasedAmount);
        token.buy{value: ethPaid}();
        console.log("bob buys", formatUnit(tokenPurchasedAmount), "tokens");
        console.log("bob spends", formatUnit(ethPaid), " in ETH for tokens");

        uint256 bobNewBalance = token.balanceOf(bob);
        assertGt(bobNewBalance, bobOldBalance);
        console.log("bob's resulting balance:", formatUnit(bobNewBalance), "tokens");
    }

    function test_should_burn_fees_weekly_on_admin_request_emits_TradeFeesUpdated_and_FeesBurned() public {
        vm.expectEmit(true, true, true, true);
        emit ITradeable.TradeFeesUpdated(100, 100);
        token.setTradeFees(100, 100);
        console.log("deployer sets fees");

        uint256 price = 0.001 ether;
        vm.prank(alice);
        token.startVoting(price);
        console.log("alice starts a voting for a price (", formatUnit(price), ")");

        vm.warp(block.timestamp + votingTimeoutSeconds);
        vm.prank(carol);
        token.endVoting();

        uint256 ethAmount = 1 ether;
        vm.deal(bob, ethAmount);
        vm.prank(bob);
        token.buy{value: ethAmount}();
        console.log("bob spends", formatUnit(ethAmount), " in ETH for tokens");

        uint256 feeBalance = token.feeBalance();
        assertGt(feeBalance, 0);
        console.log("contract's fee balance:", formatUnit(feeBalance));

        uint256 feeBurnTimestamp = token.feeBurnTimestamp();
        uint256 sevenDays = 7 * 24 * 60 * 60;
        vm.expectRevert(abi.encodeWithSignature("BurningCooldown(uint256)", feeBurnTimestamp + sevenDays));
        token.burnFees();
        console.log("deployer can't burn the fees as 7 days hasn't passed yet");

        uint256 travelTimeSeconds = 7 * 24 * 3600;
        vm.warp(block.timestamp + travelTimeSeconds);
        console.log("... 7 days passes ...");

        vm.expectEmit(true, true, true, true);
        emit IChargeable.FeesBurned(feeBalance);
        token.burnFees();
        console.log("deployer burns fees");

        uint256 newFeeBalance = token.feeBalance();
        assertEq(newFeeBalance, 0);
        console.log("contract's fee balance:", formatUnit(newFeeBalance));
    }

    // the rest of the tests

    function test_should_upgrade() public {
        VTCTokenUpgradeableDestroyer logicV2 = new VTCTokenUpgradeableDestroyer();
        proxy.upgradeTo(address(logicV2));
        VTCTokenUpgradeableDestroyer tokenV2 = VTCTokenUpgradeableDestroyer(payable(address(proxy)));

        vm.prank(alice);
        tokenV2.makeRich(alice);

        assert(token.balanceOf(alice) == 0);
    }

    function test_allows_holder_above_01_percent_supply_to_start_voting_and_cast_initial_vote() public {
        uint256 totalSupply = token.totalSupply();
        uint256 votingBalanceThreshold = totalSupply / 1000;

        uint256 aliceBalance = token.balanceOf(alice);
        assertGe(aliceBalance, votingBalanceThreshold);

        uint256 price = 0.001 ether;
        vm.prank(alice);
        token.startVoting(price);

        bool votingActive = token.votingActive();
        assertTrue(votingActive);

        uint256 roundId = token.currentVotingRoundId();
        assertEq(roundId, 1);
    }

    function test_ends_voting_after_votingTimeout_and_sets_currentPrice_based_on_votes() public {
        uint256 priceA = 0.001 ether;
        uint256 priceB = 0.002 ether;

        vm.prank(alice);
        token.startVoting(priceA);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("AlreadyVoted()"));
        token.vote(priceB);

        uint256 totalSupply = token.totalSupply();
        uint256 votingBalanceThreshold = totalSupply / 2000;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("InsufficientVotingBalance(uint256)", votingBalanceThreshold));
        token.vote(priceB);

        uint256 transferAmount = totalSupply / 100; // 1% of total supply
        token.transfer(bob, transferAmount);

        vm.prank(bob);
        token.vote(priceB);

        vm.warp(block.timestamp + votingTimeoutSeconds);

        // can't vote
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSignature("InsufficientVotingBalance(uint256)", votingBalanceThreshold));
        token.vote(priceB);

        // but can end
        vm.prank(carol);
        token.endVoting();

        assertEq(token.currentPrice(), priceA);
    }

    function test_allows_buying_tokens() public {
        uint256 price = 0.001 ether;

        token.startVoting(price);

        vm.warp(block.timestamp + votingTimeoutSeconds);
        token.endVoting();

        uint256 oldBalance = token.balanceOf(bob);
        uint256 ethAmount = 0.01 ether;
        vm.deal(bob, ethAmount);
        vm.prank(bob);
        token.buy{value: ethAmount}();

        uint256 newBalance = token.balanceOf(bob);
        assertGt(newBalance, oldBalance);
    }

    function test_allows_selling_tokens_when_havent_voted_and_ETH_present() public {
        uint256 price = 0.001 ether;

        token.startVoting(price);

        vm.deal(address(proxy), 50000 ether);

        vm.warp(block.timestamp + votingTimeoutSeconds);
        token.endVoting();

        // transfer some tokens to sell
        uint256 sellAmount = price;
        token.transfer(carol, sellAmount);
        uint256 oldBalance = token.balanceOf(carol);

        uint256 ethAmountNeeded = (sellAmount * token.currentPrice()) / (10 ** token.decimals());
        console.log("Contract balance", address(this).balance);
        console.log("ethAmountNeeded ", ethAmountNeeded);
        console.log("token.decimals()", token.decimals());

        // sell
        vm.prank(carol);
        token.sell(sellAmount);
        uint256 newBalance = token.balanceOf(carol);
        assertLt(newBalance, oldBalance);
    }

    // Helper function to fund this contract with ETH for transfers
    receive() external payable {}
}
