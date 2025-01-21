import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const proxyModule = buildModule("ProxyModule", (m) => {
  const proxyAdminOwner = m.getAccount(0);

  // Deploy the Factory implementation contract
  const factoryImpl = m.contract("ThreeAgentFactoryV1");

  // const wethAddress = "0x4200000000000000000000000000000000000006"; // Base WETH
  // const nonfungiblePositionManagerAddress = "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1"; // Base Uniswap V3 NFT Position Manager

  const wethAddress = "0xfff9976782d46cc05630d1f6ebab18b2324d6b14"; // Sepolia WETH
  const nonfungiblePositionManagerAddress = "0x1238536071E1c677A632429e3655c799b22cDA52"; // Sepolia Uniswap V3 NFT Position Manager

  const protocolFeeRecipient = "0x4E54b5182289377058B96FD2EdFA01EaAf705Fe1";
  const protocolFeePercent = "50000000000000000";

  // Suppose your Factory has an `initialize()` function with certain parameters:
  const initializerData = m.encodeFunctionCall(factoryImpl, "initialize", [
    wethAddress,
    nonfungiblePositionManagerAddress,
    protocolFeeRecipient,
    protocolFeePercent,
  ]);

  // Deploy a TransparentUpgradeableProxy for the Factory
  const proxy = m.contract("TransparentUpgradeableProxy", [factoryImpl, proxyAdminOwner, initializerData]);

  // Extract the ProxyAdmin address from the AdminChanged event
  const proxyAdminAddress = m.readEventArgument(proxy, "AdminChanged", "newAdmin");

  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress);

  return { proxyAdmin, proxy };
});

export default proxyModule;
