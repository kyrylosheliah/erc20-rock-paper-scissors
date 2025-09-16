import { expect } from "chai";
import { network } from "hardhat";
import type { VTCTokenUpgradeable } from "../types/ethers-contracts/VTCTokenUpgradeable.ts";
import type { UpgradeableProxy } from "../types/ethers-contracts/UpgradeableProxy.ts";

const conn = await network.connect();
const { ethers } = conn;

describe("VTCTokenUpgradeable", function () {
  let token: VTCTokenUpgradeable;
  let proxy: UpgradeableProxy;
  let votingTimeoutSeconds: number;
  let deployer: any;
  let alice: any;
  let bob: any;
  let carol: any;
  let snapshotId: string;

  const formatUnitValue = "eth";
  function formatUnit_(value: any, unit: "eth" | "gwei" | "wei" = "eth") {
    value = typeof value === "bigint" ? value : BigInt(value.toString());
    if (unit === "wei") return value.toString();
    if (unit === "gwei") return ethers.formatUnits(value, "gwei") + "E+9";
    return ethers.formatEther(value) + "E+18";
  }
  function formatUnit(value: any) {
    return formatUnit_(value, formatUnitValue);
  }

  beforeEach(async function () {
    snapshotId = await conn.provider.request({ method: "evm_snapshot", params: [] });

    [deployer, alice, bob, carol] = await ethers.getSigners();

    votingTimeoutSeconds = 60;

    // // Direct deployment
    // const Factory = await ethers.getContractFactory("VTCTokenUpgradeable");
    // token = await Factory.connect(deployer).deploy(
    //   "Voteable Tradeable Chargeable Token", "VTC", votingTimeoutSeconds
    // );
    // await token.waitForDeployment();
    // tokenContractAddress = token.getAddress();

    // Upgradeable deployment
    const LogicFactory = await ethers.getContractFactory("VTCTokenUpgradeable");
    const logic = await LogicFactory.connect(deployer).deploy();
    await logic.waitForDeployment();
    const initializeData = LogicFactory.interface.encodeFunctionData(
      "VTCTokenInitialize",
      [ "Voteable Tradeable Chargeable Token", "VTC", 18, votingTimeoutSeconds ]
    );
    const ProxyFactory = await ethers.getContractFactory("UpgradeableProxy");
    proxy = (await ProxyFactory.connect(deployer).deploy(logic.getAddress(), deployer.address, initializeData));
    await proxy.waitForDeployment();
    const proxyContractAddress = await proxy.getAddress();
    token = LogicFactory.attach(proxyContractAddress);

    // send ETH to contract
    const fundEthAmount = ethers.parseEther("1000");
    const storageContractAddress = await proxy.getAddress();
    await deployer.sendTransaction({ to: storageContractAddress, value: fundEthAmount });
    // const storageBalance = await ethers.provider.getBalance(storageContractAddress);
    // console.log("proxy (storage) contract balance is:", storageBalance);

    await token.connect(deployer).mint(deployer.address, ethers.parseEther("1000"));
    await token.connect(deployer).mint(alice.address, ethers.parseEther("1000"));
    await token.connect(deployer).mint(bob.address, ethers.parseEther("0.5")); // below 0.05%
    // carol has 0

    const totalSupply = await token.totalSupply();
    expect(totalSupply).to.be.gt(0);
  });

  afterEach(async () => {
    // revert snapshot to clean state
    await conn.provider.request({ method: "evm_revert", params: [snapshotId] });
  });

  // task tests

  it("should change votingTimestamp, votingNumber with startVoting; emits VotingStarted", async function () {
    const price = ethers.parseEther("0.001");

    await expect(token.connect(alice).startVoting(price)).to.emit(token, "VotingStarted");
    console.log(`alice starts a voting with ${formatUnit(price)}`);

    expect(await token.votingActive()).to.equal(true);
    const roundId = await token.currentVotingRoundId();
    expect(roundId).to.equal(1);

    const votingTimestamp = await token.votingTimestamp();
    expect(votingTimestamp).to.be.gt(0);
    console.log(`voting timestamp: ${votingTimestamp}`);
    console.log(`voting round: ${roundId}`);

    const totalSupply = await token.totalSupply();
    console.log(`totalSupply: ${formatUnit(totalSupply)}`);
  });

  it("should prevent accounts with <0.05% of totalSuppy ownership from voting; emits Voted", async function () {
    const totalSupply = await token.totalSupply();
    console.log(`totalSupply is ${formatUnit(totalSupply)}`);
    const threshold = totalSupply / 2000n; // 0.05%
    console.log(`voting threshold is ${formatUnit(threshold)}`);

    const aliceBalance = await token.balanceOf(alice.address);
    console.log(`alice's balance: ${formatUnit(aliceBalance)}`);
    expect(aliceBalance >= threshold);
    console.log(`alice is above the threshold`);

    const price = ethers.parseEther("0.001");

    await expect(token.connect(alice).startVoting(price)).to.emit(token, "VotingStarted");
    console.log(`alice starts a voting`);

    const bobBalance = await token.balanceOf(bob.address);
    expect(bobBalance < threshold).to.be.true;
    console.log(`bob's balance: ${formatUnit(bobBalance)}`);
    await expect(
      token.connect(bob).vote(price)
    ).to.be.revertedWithCustomError(token, "InsufficientVotingBalance").withArgs(threshold);
    console.log(`bob is below the threshold`);

    const transferAmount = threshold - bobBalance + 1n;
    await token.connect(deployer).transfer(bob.address, transferAmount);
    console.log(`deployer transfers ${formatUnit(transferAmount)} to bob to reach the voting threshold`);

    const newBobBalance = await token.balanceOf(bob.address);
    expect(newBobBalance).to.be.gte(threshold);
    console.log(`bob's balance: ${formatUnit(newBobBalance)} now`);

    await expect(token.connect(bob).vote(price)).to.emit(token, "Voted");
    console.log(`bob voted successfully`);
  });

  it("should prevent double-spending on voting and transfers for voters", async function () {
    const price = ethers.parseEther("0.001");

    const aliceBalance = await token.balanceOf(alice.address);
    console.log(`alice's balance: ${formatUnit(aliceBalance)}`);
    await token.connect(alice).startVoting(price);
    console.log(`alice starts a voting for a price (${formatUnit(price)})`);

    const bobBalance = await token.balanceOf(bob.address);
    console.log(`bob's balance: ${formatUnit(bobBalance)} tokens`);
    expect(token.connect(alice).startVoting(price)).to.be.revertedWithCustomError(token, "VotingActive");
    console.log(`bob's vote was reverted due to insufficient balance`);

    const aliceTransferAmount = aliceBalance / 2n;
    await expect(
      token.connect(alice).transfer(bob.address, aliceTransferAmount)
    ).to.be.revertedWithCustomError(token, "VotingParticipation").withArgs(alice.address);
    console.log(`alice's transfer to bob was reverted due to voting participation`);

    const bobTransferAmount = (await token.connect(bob).balanceOf(bob)) / 100n; // 1%
    await expect(
      token.connect(bob).transfer(alice.address, bobTransferAmount)
    ).to.be.revertedWithCustomError(token, "VotingParticipation").withArgs(alice.address);

    const decimals = await token.decimals();
    const sellAmount = 10n**decimals / 1000n;
    await expect(
      token.connect(alice).sell(sellAmount)
    ).to.be.revertedWithCustomError(token, "VotingParticipation").withArgs(alice.address);
  });

  it("allows buying and selling with sufficient ETH; emits Bought and Sold", async function () {
    const price = 1n; // 1 to 1

    await token.connect(alice).startVoting(price);
    console.log(`alice starts a voting for a price (${formatUnit(price)})`);
    await ethers.provider.send("evm_increaseTime", [votingTimeoutSeconds]);
    await ethers.provider.send("evm_mine", []);
    await token.connect(carol).endVoting();
    console.log(`the voting ended`);

    const sellAmount = 1000n;
    await token.connect(deployer).transfer(carol.address, sellAmount);
    const oldBalance = await token.balanceOf(carol.address);
    console.log(`carol's staring balance: ${formatUnit(oldBalance)}`);

    await expect(token.connect(carol).sell(sellAmount)).to.emit(token, "Sold");
    console.log(`carol sells ${formatUnit(sellAmount)} in tokens`);

    const newBalance = await token.balanceOf(carol.address);
    expect(newBalance).to.be.lt(oldBalance);
    console.log(`carol's resulting balance: ${formatUnit(newBalance)}`);

    // Also test buy emits Bought and increases balance
    const bobOldBalance = await token.balanceOf(bob.address);
    console.log(`bob's starting balance: ${formatUnit(bobOldBalance)} tokens`);
    const ethAmount = ethers.parseEther("0.001");
    await expect(token.connect(bob).buy({ value: ethAmount })).to.emit(token, "Bought");
    console.log("bob buys tokens for", formatUnit(ethAmount)," ETH");
    const bobNewBalance = await token.balanceOf(bob.address);
    expect(bobNewBalance).to.be.gt(bobOldBalance);
    console.log(`bob's resulting balance: ${formatUnit(bobNewBalance)} tokens`);
  });

  it("should burn fees weekly on admin's request; emits TradeFeesUpdated and FeesBurned)", async function () {
    await expect(token.connect(deployer).setTradeFees(100, 100)).to.emit(token, "TradeFeesUpdated");
    console.log(`deployer sets fees`);

    const price = ethers.parseEther("0.001");
    await token.connect(alice).startVoting(price);
    console.log(`alice starts a voting for a price (${formatUnit(price)})`);

    await ethers.provider.send("evm_increaseTime", [votingTimeoutSeconds]);
    await ethers.provider.send("evm_mine", []);
    await token.connect(carol).endVoting();

    const ethAmount = ethers.parseEther("1");
    await token.connect(bob).buy({ value: ethAmount });
    console.log("bob buys tokens for", formatUnit(ethAmount)," ETH");

    const feeBalance = await token.feeBalance();
    expect(feeBalance).to.be.gt(0);
    console.log(`contract's fee balance: ${formatUnit(feeBalance)}`);

    const feeBurnTimestamp = await token.feeBurnTimestamp();
    const sevenDays = 7n * 24n * 60n * 60n;
    await expect(
      token.connect(deployer).burnFees()
    ).to.be.revertedWithCustomError(token, "BurningCooldown").withArgs(feeBurnTimestamp + sevenDays);
    console.log(`deployer can't burns the fees as 7 days hasn't passed yet`);

    const travelTimeSeconds = 7 * 24 * 3600;
    await ethers.provider.send("evm_increaseTime", [travelTimeSeconds]);
    await ethers.provider.send("evm_mine", []);
    console.log(`... 7 days passes ...`);

    await expect(token.connect(deployer).burnFees()).to.emit(token, "FeesBurned");
    console.log(`deployer burns fees`);

    const newFeeBalance = await token.feeBalance();
    expect(newFeeBalance).to.equal(0);
    console.log(`contract's fee balance: ${formatUnit(newFeeBalance)}`);
  });

  // the rest of the tests

  it("should upgrade", async function () {
    const LogicV2Factory = await ethers.getContractFactory("VTCTokenUpgradeable");
    const logicV2 = await LogicV2Factory.connect(deployer).deploy();
    await logicV2.waitForDeployment();
    await proxy.connect(deployer).upgradeTo(logicV2.getAddress());
    const proxyContractAddress = await proxy.getAddress();
    const tokenV2 = LogicV2Factory.attach(proxyContractAddress);

    const price = ethers.parseEther("0.001");
    await expect(tokenV2.connect(alice).startVoting(price)).to.emit(tokenV2, "VotingStarted");
    expect(await tokenV2.votingActive()).to.be.true;
  });

  it("allows a holder >= 0.1% supply to start voting and to cast initial vote", async function () {
    const totalSupply = await token.totalSupply();
    const votingBalanceThreshold = totalSupply / 1000n;

    const aliceBalance = await token.balanceOf(alice.address);
    expect(aliceBalance).to.be.gte(votingBalanceThreshold);

    const price = ethers.parseEther("0.001");
    await token.connect(alice).startVoting(price);

    const votingActive = await token.votingActive();
    expect(votingActive).to.equal(true);

    const roundId = await token.currentVotingRoundId();
    expect(roundId).to.equal(1);
  });

  it("ends voting after votingTimeout and sets currentPrice based on votes", async function () {
    const priceA = ethers.parseEther("0.001");
    const priceB = ethers.parseEther("0.002");

    await token.connect(alice).startVoting(priceA);

    await expect(token.connect(alice).vote(priceB)).to.be.revertedWithCustomError(token, "AlreadyVoted");

    const totalSupply = await token.totalSupply();
    const votingBalanceThreshold = totalSupply / 2000n;

    await expect(
      token.connect(bob).vote(priceB)
    ).to.be.revertedWithCustomError(token, "InsufficientVotingBalance").withArgs(votingBalanceThreshold);

    const transferAmount = (await token.totalSupply()) / 100n; // 1% of total supply
    await token.connect(deployer).transfer(bob.address, transferAmount);
    expect(await token.connect(bob).vote(priceB)).to.be.ok;

    await ethers.provider.send("evm_increaseTime", [votingTimeoutSeconds]);
    await ethers.provider.send("evm_mine", []);

    // can't vote
    await expect(
      token.connect(carol).vote(priceB)
    ).to.be.revertedWithCustomError(token, "InsufficientVotingBalance").withArgs(votingBalanceThreshold);
    // but can end
    await token.connect(carol).endVoting();

    expect(await token.currentPrice()).to.be.eq(priceA);
  });

  it("allows buying tokens", async function () {
    const price = ethers.parseEther("0.001");

    await token.connect(deployer).startVoting(price);

    await ethers.provider.send("evm_increaseTime", [votingTimeoutSeconds]);
    await ethers.provider.send("evm_mine", []);
    await token.endVoting();

    const oldBalance = await token.balanceOf(bob.address);
    await token.connect(bob).buy({ value: ethers.parseEther("0.01") });

    const newBalance = await token.balanceOf(bob.address);
    expect(newBalance).to.be.gt(oldBalance);
  });

  it("allows selling tokens when haven't voted and ETH present", async function () {
    const price = ethers.parseEther("1"); // 1 to 1 price

    await token.connect(deployer).startVoting(price);

    await ethers.provider.send("evm_increaseTime", [votingTimeoutSeconds]);
    await ethers.provider.send("evm_mine", []);
    await token.endVoting();

    // transfer some tokens to sell
    const sellAmount = price * 1000n;
    await token.connect(deployer).transfer(carol.address, sellAmount);
    const oldBalance = await token.balanceOf(carol.address);

    // sell
    await token.connect(carol).sell(sellAmount);
    const newBalance = await token.balanceOf(carol.address);
    expect(newBalance < oldBalance).to.be.true;
  });
});
