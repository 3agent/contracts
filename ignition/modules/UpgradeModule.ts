import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import proxyModule from "./ProxyModule";

const upgradeModule = buildModule("UpgradeModule", (m) => {
  const proxyAdminOwner = m.getAccount(0);

  const { proxyAdmin, proxy } = m.useModule(proxyModule);

  const factoryV2 = m.contract("ThreeAgentFactoryV2");

  m.call(proxyAdmin, "upgradeAndCall", [proxy, factoryV2, "0x"], { from: proxyAdminOwner });

  return { proxy, proxyAdmin, factoryV2 };
});

export default upgradeModule;
