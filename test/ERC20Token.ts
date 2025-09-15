import { expect } from "chai";
import { network } from "hardhat";
import type { ERC20TokenUpgradeable } from "../types/ethers-contracts/ERC20TokenUpgradeable.ts";
import type { UpgradeableProxy } from "../types/ethers-contracts/UpgradeableProxy.ts";

const conn = await network.connect();
const { ethers } = conn;

describe("ERC20Token: IERC20 token implementation", function () {
  let token: ERC20TokenUpgradeable;
  let tokenContractAddress: string;
  let proxy: UpgradeableProxy;
  let deployer: any;
  let alice: any;
  let bob: any;
  let snapshotId: string;

  beforeEach(async () => {
    snapshotId = await conn.provider.request({ method: "evm_snapshot", params: [] });

    [deployer, alice, bob] = await ethers.getSigners();

    // Upgradeable deployment
    const LogicFactory = await ethers.getContractFactory("VTCTokenUpgradeable");
    const logic = await LogicFactory.connect(deployer).deploy();
    await logic.waitForDeployment();
    const initializeData = LogicFactory.interface.encodeFunctionData(
      "ERC20TokenInitialize",
      [ "ERC20 Token", "ET"]
    );
    const ProxyFactory = await ethers.getContractFactory("UpgradeableProxy");
    proxy = (await ProxyFactory.connect(deployer).deploy(logic.getAddress(), deployer.address, initializeData));
    await proxy.waitForDeployment();
    const proxyContractAddress = await proxy.getAddress();
    token = LogicFactory.attach(proxyContractAddress);
    tokenContractAddress = await token.getAddress();
  });

  afterEach(async () => {
    // revert snapshot to clean state
    await conn.provider.request({ method: "evm_revert", params: [snapshotId] });
  });

  it("mints tokens correctly", async () => {
    await token.mint(alice.address, ethers.parseEther("100"));
    expect(await token.totalSupply()).to.equal(ethers.parseEther("100"));
    expect(await token.balanceOf(alice.address)).to.equal(ethers.parseEther("100"));
  });

  it("transfers tokens between accounts", async () => {
    await token.mint(alice.address, ethers.parseEther("50"));

    await token.connect(alice).transfer(bob.address, ethers.parseEther("20"));

    expect(await token.balanceOf(alice.address)).to.equal(ethers.parseEther("30"));
    expect(await token.balanceOf(bob.address)).to.equal(ethers.parseEther("20"));
  });

  it("approves and transfers with allowance", async () => {
    await token.mint(alice.address, ethers.parseEther("40"));

    await token.connect(alice).approve(bob.address, ethers.parseEther("15"));
    expect(await token.allowance(alice.address, bob.address)).to.equal(ethers.parseEther("15"));

    await token.connect(bob).transferFrom(alice.address, bob.address, ethers.parseEther("10"));

    expect(await token.balanceOf(alice.address)).to.equal(ethers.parseEther("30"));
    expect(await token.balanceOf(bob.address)).to.equal(ethers.parseEther("10"));
    expect(await token.allowance(alice.address, bob.address)).to.equal(ethers.parseEther("5"));
  });

  it("burns tokens correctly", async () => {
    await token.mint(alice.address, ethers.parseEther("25"));

    await token.connect(alice).burn(ethers.parseEther("10"));

    expect(await token.totalSupply()).to.equal(ethers.parseEther("15"));
    expect(await token.balanceOf(alice.address)).to.equal(ethers.parseEther("15"));
  });

  it("reverts when burning more than balance", async () => {
    await token.mint(alice.address, ethers.parseEther("5"));

    await expect(
      token.connect(alice).burn(ethers.parseEther("10"))
    ).to.be.revertedWithCustomError(token, "ERC20InsufficientBalance");
  });

  it("reverts when transfer amount exceeds balance", async () => {
    await token.mint(alice.address, ethers.parseEther("1"));
    await expect(
      token.connect(alice).transfer(bob.address, ethers.parseEther("2"))
    ).to.be.revertedWithCustomError(token, "ERC20InsufficientBalance");
  });

  it("reverts when transferFrom exceeds allowance", async () => {
    await token.mint(alice.address, ethers.parseEther("10"));
    await token.connect(alice).approve(bob.address, ethers.parseEther("5"));

    await expect(
      token.connect(bob).transferFrom(alice.address, bob.address, ethers.parseEther("7"))
    ).to.be.revertedWithCustomError(token, "ERC20InsufficientAllowance");
  });
});
