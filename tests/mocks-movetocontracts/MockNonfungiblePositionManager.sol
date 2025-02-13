// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockNonfungiblePositionManager is ERC721 {
    bool public poolInitialized;
    address public token0;
    address public token1;
    uint24 public fee;
    uint160 public sqrtPriceX96;
    int24 public tickLower;
    int24 public tickUpper;
    address public pool;

    constructor() ERC721("Uniswap V3 Positions NFT-V1", "UNI-V3-POS") {
        pool = address(this);
    }

    function createAndInitializePoolIfNecessary(
        address _token0,
        address _token1,
        uint24 _fee,
        uint160 _sqrtPriceX96
    ) external returns (address) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        sqrtPriceX96 = _sqrtPriceX96;
        poolInitialized = true;
        return pool;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(poolInitialized, "Pool not initialized");
        
        IERC20(params.token0).transferFrom(msg.sender, address(this), params.amount0Desired);
        IERC20(params.token1).transferFrom(msg.sender, address(this), params.amount1Desired);
        
        tokenId = 1;
        liquidity = 1000000;
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
        
        _mint(params.recipient, tokenId);
        
        return (tokenId, liquidity, amount0, amount1);
    }

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
}