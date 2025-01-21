import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

describe("CurvedToken", function () {
  async function deployCurvedTokenFixture() {
    const [owner, bondingCurve, otherAccount] = await ethers.getSigners();
    const name = "Curved Token";
    const symbol = "CRV";
    const CurvedToken = await ethers.getContractFactory("CurvedToken");
    const token = await CurvedToken.deploy(bondingCurve.address, name, symbol);

    return { token, owner, bondingCurve, otherAccount, name, symbol };
  }

  describe("Deployment", function () {
    it("Should set the bondingCurve address correctly", async function () {
      const { token, bondingCurve } = await loadFixture(deployCurvedTokenFixture);
      expect(await token.bondingCurve()).to.equal(bondingCurve.address);
    });

    it("Should have the correct name and symbol", async function () {
      const { token, name, symbol } = await loadFixture(deployCurvedTokenFixture);
      expect(await token.name()).to.equal(name);
      expect(await token.symbol()).to.equal(symbol);
    });

    it("Should have zero total supply after deployment", async function () {
      const { token } = await loadFixture(deployCurvedTokenFixture);
      const totalSupply = await token.totalSupply();
      expect(totalSupply).to.equal(0);
    });

    it("BondingCurve address should have zero balance initially", async function () {
      const { token, bondingCurve } = await loadFixture(deployCurvedTokenFixture);
      const balance = await token.balanceOf(bondingCurve.address);
      expect(balance).to.equal(0);
    });
  });

  describe("Burn and Mint functionality", function () {
    it("Should allow the bondingCurve address to mint and then burn tokens from an account", async function () {
      const { token, bondingCurve, otherAccount } = await loadFixture(deployCurvedTokenFixture);

      // BondingCurve mints tokens to itself
      const mintAmount = 1000n;
      await token.connect(bondingCurve).mint(bondingCurve.address, mintAmount);

      // Check balances after mint
      const initialBondingCurveBalance = await token.balanceOf(bondingCurve.address);
      const initialTotalSupply = await token.totalSupply();
      expect(initialBondingCurveBalance).to.equal(mintAmount);
      expect(initialTotalSupply).to.equal(mintAmount);

      // Transfer some tokens from bondingCurve to otherAccount
      const transferAmount = 1000n;
      await token.connect(bondingCurve).transfer(otherAccount.address, transferAmount);

      // Check balances before burn
      const initialOtherAccountBalance = await token.balanceOf(otherAccount.address);
      expect(initialOtherAccountBalance).to.equal(transferAmount);

      // BondingCurve burns tokens from otherAccount
      const burnAmount = 500n;
      await token.connect(bondingCurve).burn(otherAccount.address, burnAmount);

      const finalOtherAccountBalance = await token.balanceOf(otherAccount.address);
      const finalTotalSupply = await token.totalSupply();

      expect(finalOtherAccountBalance).to.equal(initialOtherAccountBalance - burnAmount);
      expect(finalTotalSupply).to.equal(initialTotalSupply - burnAmount);
    });
  });
});
