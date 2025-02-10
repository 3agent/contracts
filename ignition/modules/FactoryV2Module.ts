import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import upgradeModule from "./UpgradeModule";

const factoryModule = buildModule("FactoryV2Module", (m) => {
  const { proxy } = m.useModule(upgradeModule);

  // Interact with the Factory via the proxy
  const factoryV2 = m.contractAt("ThreeAgentFactoryV2", proxy);

  return { factoryV2 };
});

export default factoryModule;
