# 3agent Smart Contracts

This repo contains the **smart contract** components for 3agent, designed to power the token bonding curve mechanism and facilitate the creation of new token–curve pairs. It uses [Hardhat](https://hardhat.org/) as the development and testing framework.

## Overview

3agent offers a no-code solution for deploying **autonomous agents** on **Base**. Agents have their own ERC20 tokens with bonding curves for trading, and can interact on X (formerly Twitter). This repository’s smart contracts define the token (with bonding curve mechanics), the bonding curve logic itself, and a factory for deploying both.


## Smart Contract Summaries

### 1. CurvedToken

An ERC20 token implementing a bonding-curve–specific mint and burn mechanism:

- **Minting/Burning**: Only allowed by the bonded contract (`BondingCurve.sol`).
- **Events**: 
  - `Minted(address to, uint256 amount, uint256 totalSupply)`
  - `Burned(address from, uint256 amount, uint256 totalSupply)`
- **Custom Errors**: e.g., `NotAuthorizedToMint`, `NotAuthorizedToBurn`, etc.
- **Constructor Arguments**: 
  - `_bondingCurve` (the BondingCurve contract address)
  - `_name` / `_symbol` for the ERC20 token

### 2. BondingCurve

Implements a **geometric (exponential) bonding curve** with Uniswap V3 integration. Key features:

- **Buy & Sell**:
  - Users can buy tokens (mints them if under the cap).
  - Users can sell tokens back (burning them and refunding ETH).
- **Finalization**:
  - On hitting the cap, automatically finalizes the curve and provides liquidity on Uniswap V3.
- **Math**: 
  - `FullMath` for precise calculations.
  - Fixed-point exponentiation `_powFixed`.
  - Curve parameters: `P0`, `RATIO`, `CAP`.
- **Events**: 
  - `Buy`, `Sell`, `Finalized`, etc.

### 3. ThreeAgentFactoryV1

A factory contract for creating:

1. **CurvedToken**  
2. **BondingCurve**  

It then wires them together so the BondingCurve can mint/burn tokens. Key points:

- **Deployment Info**: Tracks each `(token, curve)` pair along with creator and timestamp.
- **Parameters**:
  - `wethAddress`
  - `nonfungiblePositionManagerAddress` (Uniswap V3)
  - `protocolFeeRecipient`
  - `protocolFeePercent`
- **Events**:
  - `TokenAndCurveCreated`
  - Various update events (fee params, WETH address, etc.)

## Hardhat Configuration

Here’s the essential Hardhat setup (`hardhat.config.ts`):

- **Compiler**: Solidity `0.8.28`
- **Optimizer**: Enabled, runs = 200
- **Networks**:
  - `hardhat` (local)
  - `sepolia`
  - `baseSepolia`
- **Etherscan** verification keys for:
  - `sepolia`
  - `baseSepolia`
- **Mocha** test timeout of `100000ms`

### Environment Variables

You can configure the networks and accounts in a `.env` file (not committed). For example:
