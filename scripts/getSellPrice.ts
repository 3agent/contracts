// scripts/testGetBuyPrice.ts
import { ethers } from "hardhat";
import FACTORY_ABI from "../artifacts/contracts/ThreeAgentFactoryV1.sol/ThreeAgentFactoryV1.json";
import BONDING_CURVE_ABI from "../artifacts/contracts/BondingCurve.sol/BondingCurve.json";

async function main() {
  // 1. Get Signers
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  // 2. References to your contracts
  //    - Suppose you have a Factory contract that creates an agent
  //    - Suppose the script needs to call the buy() function on the newly created BondingCurve
  //    - Suppose finalization might be triggered automatically or manually
  const FACTORY_ADDRESS = "0x5efCB9C5924Fa3c52dda489d12070A0703e9F72E";

  // 3. Attach to the Factory
  const factory = new ethers.Contract(FACTORY_ADDRESS, FACTORY_ABI.abi, deployer);

  // 4. Create Agent (Token + Curve) via the Factory
  console.log("Creating a new agent (token + curve)...");
  const createTx = await factory.createTokenAndCurve("MyAgent", "AGT");
  const receiptCreate = await createTx.wait();

  // Parse logs or read from an event if the factory emits something like `TokenAndCurveCreated`
  // For example, if the factory has `event TokenAndCurveCreated(address indexed creator, address token, address curve)`
  // Then parse it:
  let curveAddress: string | undefined;
  for (const log of receiptCreate.logs) {
    try {
      // e.g., if the factory has an interface
      // we can parse the event
      const parsed = factory.interface.parseLog(log);
      if (parsed?.name === "TokenAndCurveCreated") {
        curveAddress = parsed.args.curve;
        console.log("New curve created at:", curveAddress);
      }
    } catch (err) {
      // not a matching event, ignore
    }
  }

  if (!curveAddress) {
    throw new Error("Could not find curve address from logs!");
  }

  const totalSupply = 150_000_000;
  const bondingCurve = new ethers.Contract(curveAddress, BONDING_CURVE_ABI.abi, deployer);
  // 3. Define test scenarios
  //    Each scenario is { supply, amount } for getBuyPrice(supply, amount)
  const scenarios = [
    { supply: 10, amount: 1 }, // Buying 1M tokens at supply=0
    { supply: 10_0000, amount: 1_000 }, // Buying 1M at supply=10M
    { supply: 50_000_000, amount: 10_000_000 }, // Buying 5M at supply=50M
    { supply: 100_000_000, amount: 10_000_000 }, // Buying 10M at supply=100M
    { supply: 150_000_000, amount: 100_000_000 }, // Another scenario
  ];

  console.log("Testing getBuyPrice() in Ether for large buys...\n");

  // 4. Loop through scenarios, call getBuyPrice, and log the result in ETH
  for (const { supply, amount } of scenarios) {
    const priceWei = await bondingCurve.getSellPrice(supply, amount);
    // Convert from wei to ETH using formatEther
    const priceEth = ethers.formatEther(priceWei);

    console.log(`Supply=${supply}, Amount=${amount} => Price = ${priceEth} ETH`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Script error:", error);
    process.exit(1);
  });
