import { expect } from "chai";
import { ignition, ethers } from "hardhat";

import ProxyModule from "../ignition/modules/ProxyModule";
import UpgradeModule from "../ignition/modules/UpgradeModule";

describe("Demo Proxy", function () {
  describe("Proxy interaction", function () {
    it("Should be interactable via proxy", async function () {
      const [, otherAccount] = await ethers.getSigners();

      const { factory } = await ignition.deploy(ProxyModule);

      expect(await factory.connect(otherAccount));
    });
  });

  describe("Upgrading", function () {
    it("Should have upgraded the proxy to DemoV2", async function () {
      const [, otherAccount] = await ethers.getSigners();

      const { factoryV2 } = await ignition.deploy(UpgradeModule);

      expect(await factoryV2.connect(otherAccount));
    });
  });
});