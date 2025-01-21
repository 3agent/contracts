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
  const FACTORY_ADDRESS = "0x72985DB0AD8030E54CA2B8613ad402FFAfD5C9b4";

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

  // 5. Attach to the new BondingCurve
  const bondingCurve = new ethers.Contract(curveAddress, BONDING_CURVE_ABI.abi, deployer);
  const buyAmount = 100_000_000; // 1000 tokens in 'whole token' if your contract does internal scaling.
  const buyValue = ethers.parseEther("20"); // Provide 3 ETH to ensure it definitely surpasses 2 ETH cost.

  const buyTx = await bondingCurve.buy(buyAmount, { value: buyValue });
  const buyReceipt = await buyTx.wait();
  console.log("Buy transaction confirmed in block", buyReceipt.blockNumber);
  for (const log of buyReceipt.logs) {
    try {
      const parsed = bondingCurve.interface.parseLog(log);
      console.log(parsed?.name);
      console.log(parsed?.args);
    } catch (err) {
      // If parseLog fails, it means this log wasn't from our BondingCurve
    }
  }

  const buyTx2 = await bondingCurve.buy(buyAmount, { value: buyValue });
  const buyReceipt2 = await buyTx.wait();
  console.log("Buy transaction confirmed in block", buyReceipt.blockNumber);
  for (const log of buyReceipt2.logs) {
    try {
      const parsed = bondingCurve.interface.parseLog(log);
      console.log(parsed?.name);
      console.log(parsed?.args);
    } catch (err) {
      // If parseLog fails, it means this log wasn't from our BondingCurve
    }
  }

  // 9. Verify if finalized
  const nowFinalized = await bondingCurve.finalized();
  console.log("Now finalized?", nowFinalized);

  console.log("Done!");
}

// Hardhat entry point
main().catch((error) => {
  console.error("Script error:", error);
  process.exitCode = 1;
});
