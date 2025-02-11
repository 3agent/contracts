import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, ContractFactory } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("BondingCurve", function () {
  let bondingCurve: any;
  let curveAddress: string;
  let tokenAddress: string;
  let token: any;
  let weth: any;
  let nonfungiblePositionManager: any;
  let factory: any;
  let initialBalance: any;
  let owner: HardhatEthersSigner;
  let user1: HardhatEthersSigner;
  let user2: HardhatEthersSigner;
  let whale: HardhatEthersSigner;
  let whale2: HardhatEthersSigner;

  const PROTOCOL_FEE_PERCENT = ethers.parseEther("0.05"); // 5%

  before(async function () {
    [owner, user1, user2, whale, whale2] = (await ethers.getSigners()) as HardhatEthersSigner[];

    initialBalance = await ethers.provider.getBalance(owner.address);

    // Deploy mock contracts first
    const MockWETH = await ethers.getContractFactory("MockWETH");
    weth = await (await MockWETH.deploy()).waitForDeployment();

    const MockPositionManager = await ethers.getContractFactory("MockNonfungiblePositionManager");
    nonfungiblePositionManager = await (await MockPositionManager.deploy()).waitForDeployment();

    // Deploy factory first
    const Factory = await ethers.getContractFactory("ThreeAgentFactoryV1");
    factory = await (await Factory.deploy()).waitForDeployment();

    // Initialize factory
    await factory.initialize(
      await weth.getAddress(),
      await nonfungiblePositionManager.getAddress(),
      owner.address,
      PROTOCOL_FEE_PERCENT
    );

    // Create token and curve through factory
    const tx = await factory.createTokenAndCurve("Test Token", "TEST");
    const receipt = await tx.wait();

    // Get the created addresses from the event
    const event = receipt.logs.find((log: any) => log.eventName === "TokenAndCurveCreated");

    // Access token and curve addresses from the event
    tokenAddress = event.args.token;
    curveAddress = event.args.curve;

    // Get contract instances
    const TokenFactory = await ethers.getContractFactory("CurvedToken");
    const CurveFactory = await ethers.getContractFactory("BondingCurve");

    token = TokenFactory.attach(tokenAddress);
    bondingCurve = CurveFactory.attach(curveAddress);
  });

  // Rest of the test suite remains the same...

  describe("Initialization", function () {
    it("should initialize with correct parameters", async function () {
      expect(await bondingCurve.token()).to.equal(await token.getAddress());
      expect(await bondingCurve.weth()).to.equal(await weth.getAddress());
      expect(await bondingCurve.nonfungiblePositionManager()).to.equal(await nonfungiblePositionManager.getAddress());
      expect(await bondingCurve.protocolFeeRecipient()).to.equal(owner.address);
      expect(await bondingCurve.protocolFeePercent()).to.equal(PROTOCOL_FEE_PERCENT);
    });

    it("should start with zero circulating supply", async function () {
      expect(await bondingCurve.circulatingSupply()).to.equal(0n);
    });
  });

  describe("Price Calculations", function () {
    it("should revert when trying to buy zero tokens", async function () {
      await expect(bondingCurve.getBuyPrice(0n, 0n)).to.be.revertedWith("Must buy > 0 tokens");
    });
  });

  describe("Token Purchases", function () {
    it("should allow purchasing tokens", async function () {
      const amount = 1000000n; // 1M tokens
      const { cost, fee } = await bondingCurve.getBuyPrice(0n, amount);

      await expect(bondingCurve.connect(user1).buy(amount, { value: cost }))
        .to.emit(bondingCurve, "Buy")
        .withArgs(user1.address, amount, cost);

      const scaledAmount = amount * 10n ** 18n;
      expect(await token.balanceOf(user1.address)).to.equal(scaledAmount);
      expect(await bondingCurve.circulatingSupply()).to.equal(amount);
    });

    it("should allow selling tokens", async function () {
      const amount = 1000000n; // 1M tokens

      const currentSupply = await bondingCurve.circulatingSupply();
      const refund = await bondingCurve.getSellPrice(currentSupply, amount);

      const scaledAmount = amount * 10n ** 18n;
      await token.connect(user1).approve(curveAddress, scaledAmount);

      await expect(bondingCurve.connect(user1).sell(amount))
        .to.emit(bondingCurve, "Sell")
        .withArgs(user1.address, amount, refund);

      // const scaledAmount = amount * 10n ** 18n;
      expect(await token.balanceOf(user1.address)).to.equal(0n);
      expect(await bondingCurve.circulatingSupply()).to.equal(currentSupply - amount);
    });

    it("should refund excess ETH", async function () {
      const amount = 1000000n; // 1M tokens
      const { cost, fee } = await bondingCurve.getBuyPrice(await bondingCurve.circulatingSupply(), amount);

      const excess = ethers.parseEther("1");
      const initialBalance = await ethers.provider.getBalance(user2.address);

      await bondingCurve.connect(user2).buy(amount, { value: cost + excess });

      const finalBalance = await ethers.provider.getBalance(user2.address);
      expect(finalBalance).to.be.gt(initialBalance - cost - excess);
    });

    it("should revert when payment is insufficient", async function () {
      const amount = 1000000n; // 1M tokens
      const { cost, fee } = await bondingCurve.getBuyPrice(await bondingCurve.circulatingSupply(), amount);

      await expect(bondingCurve.connect(user1).buy(amount, { value: cost - 1n })).to.be.revertedWith(
        "Insufficient payment"
      );
    });
  });

  describe("Finalization", function () {
    it("should finalize when cap is reached", async function () {
      let isFinalized = false;
      let attempts = 0;
      const MAX_ATTEMPTS = 10;

      // transfer large amount of eth to user
      await whale.sendTransaction({
        to: user1.address,
        value: ethers.parseEther("9900"),
      });

      await whale2.sendTransaction({
        to: user1.address,
        value: ethers.parseEther("9900"),
      });

      console.log("user1 balance", await ethers.provider.getBalance(user1.address));

      while (!isFinalized && attempts < MAX_ATTEMPTS) {
        attempts++;
        const currentSupply = await bondingCurve.circulatingSupply();

        try {
          // Always try to buy 100M tokens
          const buyAmount = 100_000_000;
          const { cost, fee } = await bondingCurve.getBuyPrice(currentSupply, buyAmount);
          console.log("cost", cost);
          const buyTx = await bondingCurve.connect(user1).buy(buyAmount, { value: cost });
          await buyTx.wait();
        } catch (error) {
          console.log("Error during purchase:", error);
        }

        isFinalized = await bondingCurve.finalized();
        if (isFinalized) {
          break;
        }
      }

      expect(await bondingCurve.finalized()).to.be.true;
    });

    it("should not allow purchases after finalization", async function () {
      const amount = 1000000n; // 1M tokens
      await expect(bondingCurve.connect(user1).buy(amount, { value: ethers.parseEther("1") })).to.be.revertedWith(
        "Already finalized"
      );
    });

    it("should set up Uniswap V3 pool correctly", async function () {
      // Verify pool initialization
      expect(await nonfungiblePositionManager.poolInitialized()).to.be.true;

      // Verify liquidity provision
      const tokenAddress = await token.getAddress();
      const wethAddress = await weth.getAddress();
      expect(await nonfungiblePositionManager.token0()).to.equal(
        tokenAddress < wethAddress ? tokenAddress : wethAddress
      );
    });
  });

  describe("Protocol Fees", function () {
    it("should collect correct protocol fees during finalization", async function () {
      expect(await ethers.provider.getBalance(owner.address)).to.be.gt(initialBalance);
    });
  });
});
