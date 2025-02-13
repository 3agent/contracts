import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@typechain/hardhat";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-chai-matchers";

require("dotenv").config();

const SEPOLIA_URL = process.env.SEPOLIA_URL || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";

const BASE_URL = process.env.BASE_URL || "";
const BASE_SEPOLIA_URL = process.env.BASE_SEPOLIA_URL || "";
const BASESCAN_API_KEY = process.env.BASESCAN_API_KEY || "";

const PRIVATE_KEY = process.env.PRIVATE_KEY || "";
const DEV_PRIVATE_KEY = process.env.DEV_PRIVATE_KEY || "";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
      outputSelection: {
        "*": {
          "*": ["storageLayout"],
        },
      },
    },
  },
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
    alwaysGenerateOverloads: true,
    discriminateTypes: true,
  },
  sourcify: {
    enabled: true,
  },
  networks: {
    hardhat: {
      chainId: 31337,
      allowUnlimitedContractSize: true,
      gas: 12000000,
      blockGasLimit: 12000000,
    },
    base: {
      url: BASE_URL,
      accounts: [PRIVATE_KEY],
    },
    sepolia: {
      url: SEPOLIA_URL,
      accounts: [DEV_PRIVATE_KEY],
    },
    baseSepolia: {
      url: BASE_SEPOLIA_URL,
      accounts: [DEV_PRIVATE_KEY],
      chainId: 84532,
    },
  },
  etherscan: {
    apiKey: {
      base: BASESCAN_API_KEY,
      sepolia: ETHERSCAN_API_KEY,
      baseSepolia: BASESCAN_API_KEY,
    },
    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org",
        },
      },
    ],
  },
  mocha: {
    timeout: 100000,
  },
};

export default config;
