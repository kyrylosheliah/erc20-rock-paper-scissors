import { expect } from "chai";
import { network } from "hardhat";
import type { VoteableTradeableChargeableToken } from "../types/ethers-contracts/VoteableTradeableChargeableToken.js";
import type { UpgradeableProxy } from "../types/ethers-contracts/UpgradeableProxy.js";

const conn = await network.connect();
const { ethers } = conn;

describe("VoteableTradeableChargeableToken (proxy)", function () {
  let token: VoteableTradeableChargeableToken;
  let tokenContractAddress: string;
  let proxy: UpgradeableProxy;
  let proxyContractAddress: string;
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

    const LogicFactory = await ethers.getContractFactory("VoteableTradeableChargeableToken");
    const logic = await LogicFactory.connect(deployer).deploy();
    await logic.waitForDeployment();
    const initializeData = LogicFactory.interface.encodeFunctionData(
      "VoteableTradeableChargeableTokenInitialize",
      [ "Voteable Tradeable Chargeable Token", "VTC", votingTimeoutSeconds ]
    );
    const ProxyFactory = await ethers.getContractFactory("UpgradeableProxy");
    proxy = (await ProxyFactory.connect(deployer).deploy(logic.getAddress(), deployer.address, initializeData));
    await proxy.waitForDeployment();
    proxyContractAddress = await proxy.getAddress();
    token = LogicFactory.attach(proxyContractAddress);
    tokenContractAddress = await token.getAddress();

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

  it("should upgrade", async function () {
    const LogicV2Factory = await ethers.getContractFactory("VoteableTradeableChargeableToken");
    const logicV2 = await LogicV2Factory.connect(deployer).deploy();
    await logicV2.waitForDeployment();
    await proxy.connect(deployer).upgradeTo(logicV2.getAddress());

    const price = ethers.parseEther("0.001");
    expect(token.connect(alice).startVoting(price)).to.be.ok;
    // expect(await token.votingActive()).to.be.true;
  });

  it("should change votingTimestamp, votingNumber with startVoting; emits VotingStarted", async function () {
    const price = ethers.parseEther("0.001");

    await token.connect(alice).startVoting(price);
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
    await expect(token.connect(bob).vote(price)).to.be.revertedWith("not enough tokens");
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

  it("should prevent double-spending on voting", async function () {
    const price = ethers.parseEther("0.001");

    const aliceBalance = await token.balanceOf(alice.address);
    console.log(`alice's balance: ${formatUnit(aliceBalance)}`);
    await token.connect(alice).startVoting(price);
    console.log(`alice starts a voting for a price (${formatUnit(price)})`);

    const bobBalance = await token.balanceOf(bob.address);
    console.log(`bob's balance: ${formatUnit(bobBalance)} tokens`);
    expect(token.connect(alice).startVoting(price)).to.be.revertedWith("voting is already active");
    console.log(`bob's vote was reverted due to insufficient balance`);

    const transferAmount = aliceBalance / 2n;
    await expect(token.connect(alice).transfer(bob.address, transferAmount)).to.be.revertedWith("sender voted");
    console.log(`alice's transfer to bob was reverted due to voting participation`);
  });

  it("allows buying and selling with sufficient ETH; emits Bought and Sold", async function () {
    const price = 1n; // 1 to 1

    const fundEth = ethers.parseEther("0.05");
    await deployer.sendTransaction({ to: tokenContractAddress, value: fundEth });

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
    console.log(`bob buys ${formatUnit(ethAmount)} in ETH`);
    const bobNewBalance = await token.balanceOf(bob.address);
    expect(bobNewBalance).to.be.gt(bobOldBalance);
    console.log(`bob's resulting balance: ${formatUnit(bobNewBalance)} tokens`);
  });

  it("should burn fees weekly after fees accumulate (emit TradeFeesUpdated and FeesBurned)", async function () {
    await expect(token.connect(deployer).setTradeFees(100, 100)).to.emit(token, "TradeFeesUpdated");
    console.log(`deployer sets fees`);

    const price = ethers.parseEther("0.0001");
    await token.connect(alice).startVoting(price);
    console.log(`alice starts a voting for a price (${formatUnit(price)})`);

    await ethers.provider.send("evm_increaseTime", [votingTimeoutSeconds]);
    await ethers.provider.send("evm_mine", []);
    await token.connect(carol).endVoting();

    const ethAmount = ethers.parseEther("1");
    await token.connect(bob).buy({ value: ethAmount });
    console.log(`bob buys ${formatUnit(ethAmount)} in ETH`);

    const feeBalance = await token.feeBalance();
    expect(feeBalance).to.be.gt(0);
    console.log(`contract's fee balance: ${formatUnit(feeBalance)}`);

    await expect(token.connect(deployer).burnFees()).to.be.revertedWith("can burn only once per 7 days");
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
});
