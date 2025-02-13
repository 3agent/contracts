import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, ContractFactory } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { BondingCurve, CurvedToken } from "../typechain-types";

describe("ThreeAgentFactoryV1", function () {
  let factory: any;
  let weth: any;
  let nonfungiblePositionManager: any;
  let owner: HardhatEthersSigner;
  let user1: HardhatEthersSigner;
  let user2: HardhatEthersSigner;
  let protocolFeeRecipient: HardhatEthersSigner;

  const PROTOCOL_FEE_PERCENT = ethers.parseEther("0.01"); // 1%

  before(async function () {
    [owner, user1, user2, protocolFeeRecipient] = (await ethers.getSigners()) as unknown as HardhatEthersSigner[];

    // Deploy mock contracts
    const MockWETH = await ethers.getContractFactory("MockWETH");
    weth = await (await MockWETH.deploy()).waitForDeployment();

    const MockPositionManager = await ethers.getContractFactory("MockNonfungiblePositionManager");
    nonfungiblePositionManager = await (await MockPositionManager.deploy()).waitForDeployment();

    // Deploy factory
    const Factory = await ethers.getContractFactory("ThreeAgentFactoryV1");
    factory = await (await Factory.deploy()).waitForDeployment();
  });

  describe("Initialization", function () {
    it("should initialize with correct parameters", async function () {
      await factory.initialize(
        await weth.getAddress(),
        await nonfungiblePositionManager.getAddress(),
        protocolFeeRecipient.address,
        PROTOCOL_FEE_PERCENT
      );

      expect(await factory.wethAddress()).to.equal(await weth.getAddress());
      expect(await factory.nonfungiblePositionManagerAddress()).to.equal(await nonfungiblePositionManager.getAddress());
      expect(await factory.protocolFeeRecipient()).to.equal(protocolFeeRecipient.address);
      expect(await factory.protocolFeePercent()).to.equal(PROTOCOL_FEE_PERCENT);
    });

    it("should not allow reinitialization", async function () {
      await expect(
        factory.initialize(
          await weth.getAddress(),
          await nonfungiblePositionManager.getAddress(),
          protocolFeeRecipient.address,
          PROTOCOL_FEE_PERCENT
        )
      ).to.be.reverted;
    });
  });

  describe("Token and Curve Creation", function () {
    it("should create token and curve pair successfully", async function () {
      const tx = await factory.createTokenAndCurve("Test Token", "TEST");
      const receipt = await tx.wait();

      const event = receipt.logs.find((log: any) => log.eventName === "TokenAndCurveCreated");

      expect(event).to.not.be.undefined;
      expect(event.args.creator).to.equal(owner.address);

      const tokenAddress = event.args.token;
      const curveAddress = event.args.curve;

      expect(tokenAddress).to.not.equal(ethers.ZeroAddress);
      expect(curveAddress).to.not.equal(ethers.ZeroAddress);
    });

    it("should create tokens with correct configuration", async function () {
      const tx = await factory.createTokenAndCurve("Second Token", "SEC");
      const receipt = await tx.wait();

      const event = receipt.logs.find((log: any) => log.eventName === "TokenAndCurveCreated");

      const TokenFactory = await ethers.getContractFactory("CurvedToken");
      const token = TokenFactory.attach(event.args.token) as CurvedToken;

      expect(await token.name()).to.equal("Second Token");
      expect(await token.symbol()).to.equal("SEC");
      expect(await token.bondingCurve()).to.equal(event.args.curve);
    });

    it("should create curves with correct configuration", async function () {
      const deployment = await factory.getDeployment(1);
      const CurveFactory = await ethers.getContractFactory("BondingCurve");
      const curve = CurveFactory.attach(deployment.curve) as BondingCurve;

      expect(await curve.weth()).to.equal(await weth.getAddress());
      expect(await curve.nonfungiblePositionManager()).to.equal(await nonfungiblePositionManager.getAddress());
      expect(await curve.protocolFeeRecipient()).to.equal(protocolFeeRecipient.address);
      expect(await curve.protocolFeePercent()).to.equal(PROTOCOL_FEE_PERCENT);
    });
  });

  describe("Administrative Functions", function () {
    it("should allow owner to update protocol fee parameters", async function () {
      const newFeePercent = ethers.parseEther("0.02"); // 2%
      await factory.setProtocolFeeParameters(user1.address, newFeePercent);

      expect(await factory.protocolFeeRecipient()).to.equal(user1.address);
      expect(await factory.protocolFeePercent()).to.equal(newFeePercent);
    });

    it("should not allow non-owner to update fee parameters", async function () {
      await expect(factory.connect(user1).setProtocolFeeParameters(user2.address, ethers.parseEther("0.03"))).to.be
        .reverted;
    });
  });

  describe("Deployment Queries", function () {
    it("should return correct deployment information", async function () {
      const count = await factory.getDeploymentsCount();
      expect(count).to.be.gt(0n);

      const deployment = await factory.getDeployment(0);
      expect(deployment.token).to.not.equal(ethers.ZeroAddress);
      expect(deployment.curve).to.not.equal(ethers.ZeroAddress);
      expect(deployment.creator).to.equal(owner.address);
    });

    it("should revert when querying invalid deployment index", async function () {
      const count = await factory.getDeploymentsCount();
      await expect(factory.getDeployment(count)).to.be.revertedWith("Invalid index");
    });
  });

  describe("Integration Tests", function () {
    it("should allow token purchases through created curve", async function () {
      // Create new token and curve
      const tx = await factory.createTokenAndCurve("Test Token 3", "TT3");
      const receipt = await tx.wait();

      const event = receipt.logs.find((log: any) => log.eventName === "TokenAndCurveCreated");

      // Get contract instances
      const CurveFactory = await ethers.getContractFactory("BondingCurve");
      const TokenFactory = await ethers.getContractFactory("CurvedToken");

      const curve = CurveFactory.attach(event.args.curve) as BondingCurve;
      const token = TokenFactory.attach(event.args.token) as CurvedToken;

      // Purchase tokens
      const amount = 1000000n; // 1M tokens
      const { cost, fee } = await curve.getBuyPrice(0n, amount);

      await curve.connect(user1).buy(amount, { value: cost });

      expect(await token.balanceOf(user1.address)).to.equal(amount * 10n ** 18n);
    });
  });
});
