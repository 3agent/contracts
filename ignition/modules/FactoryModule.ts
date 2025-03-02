import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import proxyModule from "./ProxyModule";

const factoryModule = buildModule("FactoryModule", (m) => {
  const { proxy } = m.useModule(proxyModule);

  // Interact with the Factory via the proxy
  const factory = m.contractAt("ThreeAgentFactoryV1", proxy);

  return { factory };
});

export default factoryModule;
