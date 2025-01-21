import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const upgradeModule = buildModule("UpgradeToV2Module", (m) => {
  // The existing TransparentUpgradeableProxy address for your V1 contract
  const existingProxyAddress = "0xB9729FD3a848e9627770e3aFf4794d4CE683D735"; // Replace with your actual proxy address

  // The ProxyAdmin that was set as the admin of your TransparentUpgradeableProxy
  // Typically, you'd retrieve it from a prior deploy or a known address
  const proxyAdminAddress = "0x17d309380E56b9C90A5b11Ca8Ee802F00E695318";

  // 1. Deploy the new implementation (V2)
  const factoryV2Impl = m.contract("ThreeAgentFactoryV2");

  // 2. Interact with the ProxyAdmin to call `upgrade(proxy, newImplementation)`
  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress);
  m.call(proxyAdmin, "upgrade", [existingProxyAddress, factoryV2Impl]);

  // To upgrade with new initialization parameters, use `upgradeAndCall`
  //   m.call(proxyAdmin, "upgradeAndCall", [
  //     existingProxyAddress,
  //     factoryV2Impl,
  //     factoryV2Impl.interface.encodeFunctionData("initializeV2", [...args])
  //   ]);

  // Return references if needed
  return { factoryV2Impl, proxyAdmin };
});

export default upgradeModule;
