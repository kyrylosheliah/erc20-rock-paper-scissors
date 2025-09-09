import { expect } from "chai";
import { network } from "hardhat";
import type { RPSToken } from "../types/ethers-contracts/RPSToken.js";
import type { RockPaperScissors } from "../types/ethers-contracts/RockPaperScissors.js";

const conn = await network.connect();
const { ethers } = conn;

describe("RockPaperScissors with RPSToken", function () {
  let token: RPSToken;
  let rps: RockPaperScissors;
  let deployer: any;
  let alice: any;
  let bob: any;
  let snapshotId: string;

  const parse = (amt: string) => ethers.parseEther(amt);

  beforeEach(async () => {
    snapshotId = await conn.provider.request({ method: "evm_snapshot", params: [] });

    [deployer, alice, bob] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("RPSToken");
    token = await Token.connect(deployer).deploy("Rock Paper Scissors Token", "RPS");
    await token.waitForDeployment();

    const RPS = await ethers.getContractFactory("RockPaperScissors");
    rps = await RPS.connect(deployer).deploy(token.target, 3600);
    await rps.waitForDeployment();

    await token.connect(deployer).mint(alice.address, parse("1000"));
    await token.connect(deployer).mint(bob.address, parse("1000"));
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
    const stake = parse("10");

    const { salt: aliceSalt, commit: aliceCommit} = makeCommit(1);

    await token.connect(alice).approve(rps.target, stake);
    await rps.connect(alice).challengeDuel(bob.address, stake, aliceCommit);

    const { salt: bobSalt, commit: bobCommit} = makeCommit(3);
    await token.connect(bob).approve(rps.target, stake);
    await rps.connect(bob).acceptDuel(1, bobCommit);

    await rps.connect(alice).reveal(1, 1, aliceSalt);
    await rps.connect(bob).reveal(1, 3, bobSalt);

    expect(await token.balanceOf(alice.address)).to.equal(parse("1010"));
    expect(await token.balanceOf(bob.address)).to.equal(parse("990"));
  });

  it("shoud: tie -> refund", async () => {
    const stake = parse("10");

    const { salt: aliceSalt, commit: aliceCommit } = makeCommit(2);
    await token.connect(alice).approve(rps.target, stake);
    await rps.connect(alice).challengeDuel(bob.address, stake, aliceCommit);

    const { salt: bobSalt, commit: bobCommit } = makeCommit(2);
    await token.connect(bob).approve(rps.target, stake);
    await rps.connect(bob).acceptDuel(1, bobCommit);

    await rps.connect(alice).reveal(1, 2, aliceSalt);
    await rps.connect(bob).reveal(1, 2, bobSalt);

    expect(await token.balanceOf(alice.address)).to.equal(parse("1000"));
    expect(await token.balanceOf(bob.address)).to.equal(parse("1000"));
  });

  it("should: challenger reveals -> defender reveal timeout -> refund", async () => {
    const stake = parse("10");

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

    expect(await token.balanceOf(alice.address)).to.equal(parse("1000"));
    expect(await token.balanceOf(bob.address)).to.equal(parse("1000"));
  });

  it("should revert invalid reveals", async () => {
    const stake = parse("10");

    const { salt: aliceSalt, commit: aliceCommit } = makeCommit(2);
    await token.connect(alice).approve(rps.target, stake);
    await rps.connect(alice).challengeDuel(bob.address, stake, aliceCommit);

    const { salt: bobSalt, commit: bobCommit } = makeCommit(2);
    await token.connect(bob).approve(rps.target, stake);
    await rps.connect(bob).acceptDuel(1, bobCommit);

    const badSalt = ethers.hexlify(ethers.randomBytes(32));
    await expect(
      rps.connect(alice).reveal(1, 1, badSalt)
    ).to.be.revertedWith("the reveal is invalid");
  });
});
