import { expect } from "chai";
import { network } from "hardhat";
import type { VoteableTradeableChargeableToken } from "../types/ethers-contracts/VoteableTradeableChargeableToken.js";
import type { UpgradeableProxy } from "../types/ethers-contracts/UpgradeableProxy.js";

const conn = await network.connect();
const { ethers } = conn;

ethers.parseEther
describe("VoteableTradeableChargeableToken", function () {
  let token: VoteableTradeableChargeableToken;
  let tokenContractAddress: any;
  let proxy: UpgradeableProxy;
  let proxyContractAddress: any;
  let votingTimeoutSeconds: any;
  let deployer: any;
  let alice: any;
  let bob: any;
  let carol: any;
  let snapshotId: string;

  beforeEach(async function () {
    snapshotId = await conn.provider.request({ method: "evm_snapshot", params: [] });

    [deployer, alice, bob, carol] = await ethers.getSigners();

    votingTimeoutSeconds = 60;

    // // Direct deployment
    // const Factory = await ethers.getContractFactory("VoteableTradeableChargeableToken");
    // token = await Factory.connect(deployer).deploy(
    //   "Voteable Tradeable Chargeable Token", "VTC", votingTimeoutSeconds
    // );
    // await token.waitForDeployment();
    // tokenContractAddress = token.getAddress();

    // Upgradeable deployment
    const LogicFactory = await ethers.getContractFactory("VoteableTradeableChargeableToken");
    const logic = await LogicFactory.connect(deployer).deploy();
    await logic.waitForDeployment();
    const initializeData = LogicFactory.interface.encodeFunctionData(
      "VoteableTradeableChargeableTokenInitialize",
      [ "Voteable Tradeable Chargeable Token", "VTC", votingTimeoutSeconds ]
    );
    const ProxyFactory = await ethers.getContractFactory("UpgradeableProxy");
    proxy = await ProxyFactory.connect(deployer).deploy(logic.getAddress(), deployer.address, initializeData);
    await proxy.waitForDeployment();
    proxyContractAddress = await proxy.getAddress();
    token = LogicFactory.attach(proxyContractAddress);
    tokenContractAddress = token.getAddress();

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

  it("prevents users below 0.05% from voting", async function () {
    const totalSupply = await token.totalSupply();
    const votingBalanceThreshold = totalSupply / 2000n;

    const price = ethers.parseEther("0.001");
    await token.connect(alice).startVoting(price);

    const bobBalance = await token.balanceOf(bob.address);
    expect(bobBalance < votingBalanceThreshold).to.be.true;
    await expect(token.connect(bob).vote(price)).to.be.revertedWith("not enough tokens");
  });

  it("ends voting after votingTimeout and sets currentPrice based on votes", async function () {
    const priceA = ethers.parseEther("0.001");
    const priceB = ethers.parseEther("0.002");

    await token.connect(alice).startVoting(priceA);

    await expect(token.connect(alice).vote(priceB)).to.be.revertedWith("already voted");

    await expect(token.connect(bob).vote(priceB)).to.be.revertedWith("not enough tokens");

    const transferAmount = (await token.totalSupply()) / 100n; // 1% of total supply
    await token.connect(deployer).transfer(bob.address, transferAmount);
    expect(await token.connect(bob).vote(priceB)).to.be.ok;

    await ethers.provider.send("evm_increaseTime", [votingTimeoutSeconds]);
    await ethers.provider.send("evm_mine", []);

    // can't vote
    await expect(token.connect(carol).vote(priceB)).to.be.revertedWith("not enough tokens");
    // but can end
    await token.connect(carol).endVoting();

    expect(await token.currentPrice()).to.be.eq(priceA);
  });

  it("blocks transfers for voters", async function () {
    const price = ethers.parseEther("0.001");
    await token.connect(alice).startVoting(price);

    await expect( token.connect(alice).transfer(bob.address, 1)).to.be.revertedWith("sender voted");

    const transferAmount = (await token.connect(bob).balanceOf(bob)) / 100n; // 1%
    await expect( token.connect(bob).transfer(alice.address, transferAmount)).to.be.revertedWith("recipient voted");

    await expect( token.connect(alice).buy({ value: ethers.parseEther("0.01") })).to.be.revertedWith("sender voted");

    const decimals = await token.decimals();
    const sellAmount = 10n**decimals / 1000n;
    await expect(token.connect(alice).sell(sellAmount)).to.be.revertedWith("sender voted");
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
    const price = ethers.parseEther("0.000000000000000001"); // 1 to 1 price

    await token.connect(deployer).startVoting(price);

    await ethers.provider.send("evm_increaseTime", [votingTimeoutSeconds]);
    await ethers.provider.send("evm_mine", []);
    await token.endVoting();

    // send ETH to contract
    await deployer.sendTransaction({ to: tokenContractAddress, value: ethers.parseEther("0.01") });

    // transfer some tokens to sell
    const sellAmount = price * 1000n;
    await token.connect(deployer).transfer(carol.address, sellAmount);
    const oldBalance = await token.balanceOf(carol.address);

    // sell
    await token.connect(carol).sell(sellAmount);
    const newBalance = await token.balanceOf(carol.address);
    expect(newBalance < oldBalance).to.be.true;
  });

  it("allows and admin to set and burn fees weekly", async function () {
    await token.connect(deployer).setTradeFees(100, 100); // 1%

    const price = ethers.parseEther("0.001");

    await token.connect(deployer).startVoting(price);

    await ethers.provider.send("evm_increaseTime", [votingTimeoutSeconds]);
    await ethers.provider.send("evm_mine", []);
    await token.endVoting();

    await token.connect(bob).buy({ value: ethers.parseEther("1") });

    const travelTimeSeconds = 7 * 24 * 3600; // 7 days
    await ethers.provider.send("evm_increaseTime", [travelTimeSeconds]);
    await ethers.provider.send("evm_mine", []);

    await token.connect(deployer).burnFees();
  });
});
