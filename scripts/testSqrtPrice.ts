// scripts/testSqrtPrice.ts
import { ethers, network } from "hardhat";
import FACTORY_ABI from "../artifacts/contracts/ThreeAgentFactoryV1.sol/ThreeAgentFactoryV1.json";
import BONDING_CURVE_ABI from "../artifacts/contracts/BondingCurve.sol/BondingCurve.json";

const FACTORY_INTERFACE = [
  "function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool)",
];

const POOL_INTERFACE = [
  "function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)",
  "function token0() external view returns (address)",
  "function token1() external view returns (address)",
];

// Rich ETH holder on Base
const POTENTIAL_WHALES = [
  // "0x4200000000000000000000000000000000000006", // Base Weth Address
  "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14", // Sepolia Weth Address
];

const BLOCKS_TO_SEARCH = 1000; // Only search last 1000 blocks

async function getMoreETH(recipient: string) {
  for (const whale of POTENTIAL_WHALES) {
    const whaleBalance = await ethers.provider.getBalance(whale);
    console.log("\nWhale account:", whale);
    console.log("Whale balance:", ethers.formatEther(whaleBalance), "ETH");
    // Impersonate the whale account
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [whale],
    });

    // Get the signer for the whale account
    const whaleSigner = await ethers.getSigner(whale);

    // Send 1000 ETH to your account
    const tx = await whaleSigner.sendTransaction({
      to: recipient,
      value: whaleBalance - ethers.parseEther("1"), // Send 1000 ETH
    });
    await tx.wait();

    // Stop impersonating
    await network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [whale],
    });
  }
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  await getMoreETH(deployer.address);

  const FACTORY_ADDRESS = "0xf6AfE7Eb189cC8ea62a08dcea5EaE328d3Bd1040";
  // const UNISWAP_V3_FACTORY = "0x33128a8fC17869897dcE68Ed026d694621f6FDfD"; // BASE Uniswap V3 Factory
  // const WETH_ADDRESS = "0x4200000000000000000000000000000000000006"; // Base WETH

  const UNISWAP_V3_FACTORY = "0x0227628f3F023bb0B980b67D528571c95c6DaC1c"; // Sepolia Uniswap V3 Factory
  const WETH_ADDRESS = "0xfff9976782d46cc05630d1f6ebab18b2324d6b14"; // Speolia WETH

  const factory = new ethers.Contract(FACTORY_ADDRESS, FACTORY_ABI.abi, deployer);

  console.log("\nCreating a new agent...");
  const createTx = await factory.createTokenAndCurve("TestAgent", "TST");
  const receiptCreate = await createTx.wait();

  let curveAddress: string | undefined;
  for (const log of receiptCreate.logs) {
    try {
      const parsed = factory.interface.parseLog(log);
      if (parsed?.name === "TokenAndCurveCreated") {
        curveAddress = parsed.args.curve;
        console.log("New curve created at:", curveAddress);
      }
    } catch (err) {
      // not a matching event
    }
  }

  if (!curveAddress) {
    throw new Error("Could not find curve address from logs!");
  }

  const bondingCurve = new ethers.Contract(curveAddress, BONDING_CURVE_ABI.abi, deployer);

  let isFinalized = false;
  let attempts = 0;
  const MAX_ATTEMPTS = 10;

  while (!isFinalized && attempts < MAX_ATTEMPTS) {
    attempts++;
    console.log(`\nAttempt ${attempts}:`);

    const netETHRaised = await bondingCurve.netETHRaised();
    const currentSupply = await bondingCurve.circulatingSupply();
    console.log(`ETH raised: ${ethers.formatEther(netETHRaised)} ETH`);
    console.log(`Current supply: ${currentSupply.toString()} tokens`);

    try {
      // Always try to buy 100M tokens
      const buyAmount = 100_000_000;
      const buyPrice = await bondingCurve.getBuyPrice(currentSupply, buyAmount);
      console.log(`Buying ${buyAmount} tokens for ${ethers.formatEther(buyPrice)} ETH`);

      const buyTx = await bondingCurve.buy(buyAmount, { value: buyPrice });
      await buyTx.wait();
    } catch (error) {
      console.log("Error during purchase:", error);
    }

    isFinalized = await bondingCurve.finalized();
    if (isFinalized) {
      console.log("\nCurve has been finalized!");
      break;
    }

    await new Promise((resolve) => setTimeout(resolve, 1000));
  }

  if (isFinalized) {
    const finalSupply = await bondingCurve.circulatingSupply();
    const priceForOneMore = await bondingCurve.getBuyPrice(finalSupply, 1);
    console.log("\nFinal Bonding Curve State:");
    console.log("Final circulating supply:", finalSupply.toLocaleString(), "tokens");
    console.log("Final price for 1 token:", ethers.formatEther(priceForOneMore), "ETH");

    // Get finalization event details
    // Get current block
    const currentBlock = await ethers.provider.getBlockNumber();
    const fromBlock = Math.max(0, currentBlock - BLOCKS_TO_SEARCH);

    // Get finalization event details - only look at recent blocks
    const filter = bondingCurve.filters.Finalized();
    const events = await bondingCurve.queryFilter(filter, fromBlock, currentBlock);

    if (events.length > 0) {
      const finalizedEvent = events[0];
      const { tokenId, netETHRaised, amount0, amount1, liquidity } = (finalizedEvent as any).args;

      // Get the block number of finalization
      const finalizationBlock = finalizedEvent.blockNumber;

      // Query all events from this block
      const preFinEvents = await bondingCurve.queryFilter(
        bondingCurve.filters.PreFinalization(),
        finalizationBlock,
        finalizationBlock
      );

      const postWethEvents = await bondingCurve.queryFilter(
        bondingCurve.filters.PostWETHDeposit(),
        finalizationBlock,
        finalizationBlock
      );

      console.log("\nFinalization Debug Info:");
      if (preFinEvents.length > 0) {
        const { contractETHBalance, contractTokenBalance } = (preFinEvents[0] as any).args;
        console.log("Pre-finalization:");
        console.log("- Contract ETH Balance:", ethers.formatEther(contractETHBalance), "ETH");
        console.log("- Contract Token Balance:", ethers.formatUnits(contractTokenBalance, 18), "tokens");
      }

      if (postWethEvents.length > 0) {
        const { wethBalance, remainingETH } = (postWethEvents[0] as any).args;
        console.log("\nPost-WETH deposit:");
        console.log("- WETH Balance:", ethers.formatEther(wethBalance), "WETH");
        console.log("- ETH Used for Deposit:", ethers.formatEther(remainingETH), "ETH");
      }

      console.log("\nUniswap Liquidity Details:");
      console.log("amount0 added:", ethers.formatUnits(amount0, 18));
      console.log("amount1 added:", ethers.formatUnits(amount1, 18));
      console.log("Liquidity:", liquidity.toString());
    }

    const tokenAddress = await bondingCurve.token();
    console.log("\nToken address:", tokenAddress);

    // Wait a bit for Uniswap pool creation...
    console.log("\nWaiting for Uniswap pool creation...");
    await new Promise((resolve) => setTimeout(resolve, 5000));

    const uniswapFactory = new ethers.Contract(UNISWAP_V3_FACTORY, FACTORY_INTERFACE, deployer);
    const poolAddress = await uniswapFactory.getPool(tokenAddress, WETH_ADDRESS, 100);

    console.log("Uniswap V3 pool address:", poolAddress);

    // ...
    if (poolAddress !== ethers.ZeroAddress) {
      const pool = new ethers.Contract(poolAddress, POOL_INTERFACE, deployer);

      try {
        const [sqrtPriceX96, tick] = await pool.slot0();
        const token0Address = await pool.token0();

        console.log("\nUniswap V3 Pool State:");
        console.log("sqrtPriceX96:", sqrtPriceX96.toString());
        console.log("tick:", tick.toString());

        // This ratio is (token1 per token0) in the Uniswap V3 math.
        // If token0 = WETH, ratio = tokens/WETH.
        // If token1 = WETH, ratio = WETH/token.
        const ratio = (Number(sqrtPriceX96) / 2 ** 96) ** 2;

        // We want "ETH per token" for easier comparison to your bonding curve's finalPrice:
        let uniswapEthPerToken: number;
        if (token0Address.toLowerCase() === WETH_ADDRESS.toLowerCase()) {
          // If WETH is token0, then ratio is actually “(token per 1 WETH)”
          // => invert it to get “ETH per token.”
          uniswapEthPerToken = 1 / ratio;
        } else {
          // If WETH is token1, ratio = “(WETH per 1 token0)”, which is already ETH/token
          uniswapEthPerToken = ratio;
        }

        console.log("\nPrice Comparison:");
        console.log("Bonding curve final price (ETH per token):", ethers.formatEther(priceForOneMore));
        console.log("Uniswap V3 initial price (ETH per token):", Number(uniswapEthPerToken).toFixed(18));

        // const ethPriceInUSD = 1.19; // Base price
        const ethPriceInUSD = 3316.66; // Sepolia price
        const uniswapPriceFor100MTokensInETH = uniswapEthPerToken * 100_000_000;
        const uniswapPriceFor100MTokensInUSD = uniswapPriceFor100MTokensInETH * ethPriceInUSD;

        console.log("Uniswap V3 price for 100M tokens (USD):", uniswapPriceFor100MTokensInUSD.toFixed(2));

        // LOG PROTOCOL FEE
        const walletAddress = "0x4E54b5182289377058B96FD2EdFA01EaAf705Fe1";
        const walletBalance = await ethers.provider.getBalance(walletAddress);
        console.log(`\nWallet balance: ${Number(ethers.formatEther(walletBalance)).toLocaleString()} ETH`);

        const walletBalanceInUSD = Number(ethers.formatEther(walletBalance)) * ethPriceInUSD;
        console.log(`Wallet balance: ${walletBalanceInUSD.toFixed(2)} USD`);
      } catch (error) {
        console.error("Error getting pool price:", error);
      }
    } else {
      console.log("No Uniswap V3 pool found!");
    }
    // ...
  } else {
    console.log("\nFailed to finalize after", MAX_ATTEMPTS, "attempts");
    const netETHRaised = await bondingCurve.netETHRaised();
    console.log(`Final ETH raised: ${ethers.formatEther(netETHRaised)} ETH`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Script error:", error);
    process.exit(1);
  });
