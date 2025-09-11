import { expect } from "chai";
import { network } from "hardhat";
import type { RPSToken } from "../types/ethers-contracts/RPSToken.js";

const conn = await network.connect();
const { ethers } = conn;

describe("RPSToken: IERC20 implementation)", function () {
  let token: RPSToken;
  let deployer: any;
  let alice: any;
  let bob: any;
  let snapshotId: string;

  beforeEach(async () => {
    snapshotId = await conn.provider.request({ method: "evm_snapshot", params: [] });

    [deployer, alice, bob] = await ethers.getSigners();

    const TokenFactory = await ethers.getContractFactory("RPSToken");
    token = (await TokenFactory.deploy("Rock Paper Scissors Token", "RPS")) as RPSToken;
    await token.waitForDeployment();
  });

  afterEach(async () => {
    // revert snapshot to clean state
    await conn.provider.request({ method: "evm_revert", params: [snapshotId] });
  });

  // TODO: expect().to.emit()

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
    ).to.be.revertedWith("burn exceeds balance");
  });

  it("reverts when transfer amount exceeds balance", async () => {
    await token.mint(alice.address, ethers.parseEther("1"));
    await expect(
      token.connect(alice).transfer(bob.address, ethers.parseEther("2"))
    ).to.be.revertedWith("insufficient balance");
  });

  it("reverts when transferFrom exceeds allowance", async () => {
    await token.mint(alice.address, ethers.parseEther("10"));
    await token.connect(alice).approve(bob.address, ethers.parseEther("5"));

    await expect(
      token.connect(bob).transferFrom(alice.address, bob.address, ethers.parseEther("7"))
    ).to.be.revertedWith("transfer exceeds allowance");
  });
});
