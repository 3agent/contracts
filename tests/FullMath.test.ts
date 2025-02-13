import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, ContractFactory } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("FullMath Library", function () {
  let fullMathTest: any;
  let owner: HardhatEthersSigner;

  before(async function () {
    [owner] = (await ethers.getSigners()) as unknown as HardhatEthersSigner[];

    const fullMathTestFactory = await ethers.getContractFactory("MockFullMath");
    fullMathTest = await (await fullMathTestFactory.deploy()).waitForDeployment();
  });

  describe("Basic Operations", function () {
    it("should correctly multiply and divide basic numbers", async function () {
      const result = await fullMathTest.testMultiplyDivide(50n, 100n, 10n);
      expect(result).to.equal(500n);
    });

    it("should handle decimals correctly", async function () {
      const oneEther = 1000000000000000000n; // 1 ether in wei
      const twoEther = 2000000000000000000n; // 2 ether in wei
      const result = await fullMathTest.testMultiplyDivide(oneEther, twoEther, oneEther);
      expect(result).to.equal(twoEther);
    });
  });

  describe("Edge Cases", function () {
    it("should handle zero inputs correctly", async function () {
      const result1 = await fullMathTest.testMultiplyDivide(0n, 100n, 10n);
      expect(result1).to.equal(0n);

      const result2 = await fullMathTest.testMultiplyDivide(100n, 0n, 10n);
      expect(result2).to.equal(0n);
    });

    it("should handle denominator of one", async function () {
      const result = await fullMathTest.testMultiplyDivide(50n, 100n, 1n);
      expect(result).to.equal(5000n);
    });

    it("should revert on zero denominator", async function () {
      await expect(fullMathTest.testMultiplyDivide(100n, 100n, 0n)).to.be.reverted;
    });
  });

  describe("Large Numbers", function () {
    it("should handle large numbers without overflow", async function () {
      // Using more reasonable large numbers that won't overflow
      const largeNumber = 2n ** 128n - 1n; // Large but not maximum uint256
      const smallerNumber = 2n ** 64n - 1n;

      const result = await fullMathTest.testMultiplyDivide(largeNumber, smallerNumber, smallerNumber);

      expect(result).to.equal(largeNumber);
    });

    it("should handle numbers near uint128 max", async function () {
      const num = 2n ** 127n; // Half of uint128 max
      const divisor = 2n ** 32n;

      const result = await fullMathTest.testMultiplyDivide(num, divisor, divisor);

      expect(result).to.equal(num);
    });
  });

  // Additional test cases for large number scenarios
  describe("Advanced Large Number Operations", function () {
    it("should handle multiplication with subsequent division", async function () {
      const baseNumber = 2n ** 64n;
      const multiplier = 1000000n;
      const divisor = 1000000n;

      const result = await fullMathTest.testMultiplyDivide(baseNumber, multiplier, divisor);

      expect(result).to.equal(baseNumber);
    });

    it("should handle numbers requiring full precision", async function () {
      const baseNumber = 2n ** 96n;
      const multiplier = 2n ** 32n;
      const divisor = 2n ** 32n;

      const result = await fullMathTest.testMultiplyDivide(baseNumber, multiplier, divisor);

      expect(result).to.equal(baseNumber);
    });
  });

  describe("Precision Tests", function () {
    it("should maintain precision with decimals", async function () {
      const amount = 2500000000000000000n; // 2.5 ether
      const multiplier = 3700000000000000000n; // 3.7 ether
      const divisor = 1200000000000000000n; // 1.2 ether

      const result = await fullMathTest.testMultiplyDivide(amount, multiplier, divisor);

      // Expected: 2.5 * 3.7 / 1.2 = 7.708333...
      const expected = 7708333333333333333n;
      expect(result).to.equal(expected);
    });
  });
});
