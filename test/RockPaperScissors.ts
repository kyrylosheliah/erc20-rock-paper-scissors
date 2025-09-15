import { expect } from "chai";
import { network } from "hardhat";
import type { ERC20Token } from "../types/ethers-contracts/ERC20Token.ts";
import type { RockPaperScissors } from "../types/ethers-contracts/RockPaperScissors.ts";

const conn = await network.connect();
const { ethers } = conn;

describe("RockPaperScissors: an IERC20-based contract", function () {
  let token: ERC20Token;
  let rps: RockPaperScissors;
  let deployer: any;
  let alice: any;
  let bob: any;
  let snapshotId: string;

  beforeEach(async () => {
    snapshotId = await conn.provider.request({ method: "evm_snapshot", params: [] });

    [deployer, alice, bob] = await ethers.getSigners();

    const Factory = await ethers.getContractFactory("ERC20Token");
    token = await Factory.connect(deployer).deploy("Rock Paper Scissors Token", "RPS", 18);
    await token.waitForDeployment();

    const RPS = await ethers.getContractFactory("RockPaperScissors");
    rps = await RPS.connect(deployer).deploy(token.target, 3600);
    await rps.waitForDeployment();

    await token.connect(deployer).mint(alice.address, ethers.parseEther("1000"));
    await token.connect(deployer).mint(bob.address, ethers.parseEther("1000"));
  });

  afterEach(async () => {
    // revert snapshot to clean state
    await conn.provider.request({ method: "evm_revert", params: [snapshotId] });
  });

  function makeCommit(move: number) {
    const saltHex = ethers.hexlify(ethers.randomBytes(32));
    return { salt: saltHex, commit: ethers.solidityPackedKeccak256(["uint8", "bytes32"], [move, saltHex]) };
  }

  it("should: challengeDuel -> acceptDuel -> reveal x2 -> correct balance", async () => {
    const stake = ethers.parseEther("10");

    const { salt: aliceSalt, commit: aliceCommit} = makeCommit(1);

    await token.connect(alice).approve(rps.target, stake);
    await rps.connect(alice).challengeDuel(bob.address, stake, aliceCommit);

    const { salt: bobSalt, commit: bobCommit} = makeCommit(3);
    await token.connect(bob).approve(rps.target, stake);
    await rps.connect(bob).acceptDuel(1, bobCommit);

    await rps.connect(alice).reveal(1, 1, aliceSalt);
    await rps.connect(bob).reveal(1, 3, bobSalt);

    expect(await token.balanceOf(alice.address)).to.equal(ethers.parseEther("1010"));
    expect(await token.balanceOf(bob.address)).to.equal(ethers.parseEther("990"));
  });

  it("shoud: tie -> refund", async () => {
    const stake = ethers.parseEther("10");

    const { salt: aliceSalt, commit: aliceCommit } = makeCommit(2);
    await token.connect(alice).approve(rps.target, stake);
    await rps.connect(alice).challengeDuel(bob.address, stake, aliceCommit);

    const { salt: bobSalt, commit: bobCommit } = makeCommit(2);
    await token.connect(bob).approve(rps.target, stake);
    await rps.connect(bob).acceptDuel(1, bobCommit);

    await rps.connect(alice).reveal(1, 2, aliceSalt);
    await rps.connect(bob).reveal(1, 2, bobSalt);

    expect(await token.balanceOf(alice.address)).to.equal(ethers.parseEther("1000"));
    expect(await token.balanceOf(bob.address)).to.equal(ethers.parseEther("1000"));
  });

  it("should: challenger reveals -> defender reveal timeout -> refund", async () => {
    const stake = ethers.parseEther("10");

    const { salt: aliceSalt, commit: aliceCommit } = makeCommit(1);
    await token.connect(alice).approve(rps.target, stake);
    await rps.connect(alice).challengeDuel(bob.address, stake, aliceCommit);

    const { salt: bobSalt, commit: bobCommit } = makeCommit(3);
    await token.connect(bob).approve(rps.target, stake);
    await rps.connect(bob).acceptDuel(1, bobCommit);

    await rps.connect(alice).reveal(1, 1, aliceSalt);

    await conn.provider.request({ method: "evm_increaseTime", params: [3610] });
    await conn.provider.request({ method: "evm_mine", params: [] });

    await rps.connect(alice).claimTimeout(1);

    expect(await token.balanceOf(alice.address)).to.equal(ethers.parseEther("1000"));
    expect(await token.balanceOf(bob.address)).to.equal(ethers.parseEther("1000"));
  });

  it("reverts invalid reveals", async () => {
    const stake = ethers.parseEther("10");

    const { commit: aliceCommit } = makeCommit(2);
    await token.connect(alice).approve(rps.target, stake);
    await rps.connect(alice).challengeDuel(bob.address, stake, aliceCommit);

    const { commit: bobCommit } = makeCommit(2);
    await token.connect(bob).approve(rps.target, stake);
    await rps.connect(bob).acceptDuel(1, bobCommit);

    const badSalt = ethers.hexlify(ethers.randomBytes(32));
    await expect(
      rps.connect(alice).reveal(1, 1, badSalt)
    ).to.be.revertedWith("the reveal is invalid");
  });
});
