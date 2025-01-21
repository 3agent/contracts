// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// TODO: remove and replace with
// import "@openzeppelin/contracts/utils/math/Math.sol";
import "./libraries/FullMath.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/INonfungiblePositionManager.sol";
import "./interfaces/IFactory.sol";
import "./CurvedToken.sol";

/**
 * @title BondingCurve
 * @notice An exponential (geometric) bonding curve implementation with Uniswap V3 integration
 * @dev Features:
 *      - Initial token price: 0.0000001 ETH (1e11 wei)
 *      - Growth ratio: ~1.0000000037
 *      - Hard cap: 20 ETH
 *      - Automatic Uniswap V3 liquidity provision upon finalization
 */
contract BondingCurve is ReentrancyGuard {
    using FullMath for uint256;

    // ============ Constants ============

    // /// @dev Initial token price in wei
    // uint256 public constant P0 = 17000000000000; // 0.000017 ETH

    // /// @dev Growth ratio for the exponential curve
    // uint256 public constant RATIO = 1000000002500000000; // ~1.0000000025

    // /// @dev Maximum ETH that can be raised (20,000 ETH)
    // uint256 public constant CAP = 20_000 ether;

    // TODO: Dev values for Sepolia:
    // P0 = 4.9e-9 ETH => 4.9e9 wei
    uint256 public constant P0 = 4900000000;

    // RATIO ~ 1.00000000318 => 1.00000000318 * 1e18 = 1000000003180000000
    uint256 public constant RATIO = 1000000003180000000;

    // CAP ~ 6 ETH => 6 * 1e18 = 6 ETH
    uint256 public constant CAP = 6 ether;

    // ============ State Variables ============

    /// @dev The ERC20 token being sold
    CurvedToken public token;

    /// @dev Number of whole tokens currently in circulation
    uint256 public circulatingSupply;

    /// @dev Total ETH raised from token sales
    uint256 public netETHRaised;

    /// @dev Whether the bonding curve has been finalized
    bool public finalized;

    /// @dev WETH contract reference for Uniswap integration
    IWETH public immutable WETH;

    /// @dev Uniswap V3 position manager for liquidity provision
    INonfungiblePositionManager public immutable nonfungiblePositionManager;

    /// @dev Address that receives protocol fees
    address public protocolFeeRecipient;

    /// @dev Protocol fee percentage (scaled by 1e18)
    uint256 public protocolFeePercent;

    /// @dev Factory contract that deployed this curve
    address public factory;

    // ============ Events ============

    event Buy(address indexed buyer, uint256 amount, uint256 cost);
    event Sell(address indexed seller, uint256 amount, uint256 refund);
    event Finalized(
        uint256 tokenId,
        uint256 netETHRaised,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );

    event PreFinalization(
        uint256 contractETHBalance,
        uint256 contractTokenBalance
    );
    event PostWETHDeposit(uint256 wethBalance, uint256 remainingETH);

    // ============ Modifiers ============

    modifier notFinalized() {
        require(!finalized, "Already finalized");
        _;
    }

    // ============ Constructor ============

    constructor(
        address _token,
        address _wethAddress,
        address _nonfungiblePositionManagerAddress,
        address _protocolFeeRecipient,
        uint256 _protocolFeePercent,
        address _factory
    ) {
        token = CurvedToken(_token);
        WETH = IWETH(_wethAddress);
        nonfungiblePositionManager = INonfungiblePositionManager(
            _nonfungiblePositionManagerAddress
        );
        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeePercent = _protocolFeePercent;
        factory = _factory;
    }

    // ============ External Functions ============

    /**
     * @notice Allows factory to update token address
     * @param _token New token address
     */
    function setToken(address _token) external {
        require(msg.sender == factory, "Only factory can set token");
        token = CurvedToken(_token);
    }

    /**
     * @notice Allows users to buy tokens from the curve
     * @param amount Number of whole tokens to buy
     */
    function buy(uint256 amount) external payable notFinalized nonReentrant {
        require(amount > 0, "Must buy > 0 tokens");

        uint256 supply = circulatingSupply;
        uint256 cost = getBuyPrice(supply, amount);
        require(msg.value >= cost, "Insufficient payment");

        // Mint tokens to buyer
        uint256 scaledAmount = amount * (10 ** token.decimals());
        token.mint(msg.sender, scaledAmount);

        netETHRaised += cost;
        circulatingSupply += amount;

        // Refund excess ETH
        uint256 excess = msg.value - cost;
        if (excess > 0) {
            (bool refundSuccess, ) = msg.sender.call{value: excess}("");
            require(refundSuccess, "Refund failed");
        }

        emit Buy(msg.sender, amount, cost);

        // Finalize if cap reached
        if (netETHRaised >= CAP) {
            finalize();
        }
    }

    /**
     * @notice Allows users to sell tokens back to the curve
     * @param amount Number of whole tokens to sell
     */
    function sell(uint256 amount) external notFinalized nonReentrant {
        require(amount > 0, "Must sell > 0 tokens");
        require(amount <= circulatingSupply, "Not enough supply in curve");

        uint256 supply = circulatingSupply;
        uint256 refund = getSellPrice(supply, amount);
        require(refund > 0, "Refund=0? Not worth selling");
        require(
            address(this).balance >= refund,
            "Contract lacks ETH to sell tokens"
        );

        // Transfer and burn tokens
        uint256 scaledAmount = amount * (10 ** token.decimals());
        bool success = token.transferFrom(
            msg.sender,
            address(this),
            scaledAmount
        );
        require(success, "Token transfer failed");
        token.burn(address(this), scaledAmount);

        circulatingSupply -= amount;

        // Send ETH refund
        (bool sent, ) = msg.sender.call{value: refund}("");
        require(sent, "ETH send failed");

        emit Sell(msg.sender, amount, refund);
    }

    // ============ Public View Functions ============

    /**
     * @notice Calculates price to buy tokens from the curve
     * @param supply Current token supply
     * @param amount Amount of tokens to buy
     * @return Price in wei
     */
    function getBuyPrice(
        uint256 supply,
        uint256 amount
    ) public pure returns (uint256) {
        require(amount > 0, "Must buy > 0 tokens");

        uint256 rPowSupply = _powFixed(RATIO, supply);
        uint256 rPowAmount = _powFixed(RATIO, amount);
        uint256 numerator = rPowAmount - 1e18;
        uint256 denominator = RATIO - 1e18;
        uint256 fraction = FullMath.mulDiv(numerator, 1e18, denominator);
        uint256 geometric = FullMath.mulDiv(rPowSupply, fraction, 1e18);
        uint256 cost = FullMath.mulDiv(P0, geometric, 1e18);

        return cost;
    }

    /**
     * @notice Calculates refund amount for selling tokens back to curve
     * @param supply Current token supply
     * @param amount Amount of tokens to sell
     * @return Refund amount in wei
     */
    function getSellPrice(
        uint256 supply,
        uint256 amount
    ) public pure returns (uint256) {
        require(amount > 0 && amount <= supply, "Invalid sell amount");
        uint256 totalNow = _totalCost(supply);
        uint256 totalAfter = _totalCost(supply - amount);
        return totalNow - totalAfter;
    }

    // ============ Internal Functions ============

    /**
     * @dev Handles curve finalization and Uniswap V3 liquidity provision
     */
    function finalize() internal {
        finalized = true;

        // Take protocol fee
        uint256 totalETH = address(this).balance;
        uint256 protocolFee = (totalETH * protocolFeePercent) / 1e18;
        uint256 remainingETH = totalETH - protocolFee;

        (bool feeSent, ) = protocolFeeRecipient.call{value: protocolFee}("");
        require(feeSent, "Protocol fee transfer failed");

        // Mint remaining tokens to reach 1B supply
        uint256 finalTotalSupply = 1_000_000_000 * (10 ** 18);
        uint256 currentSupply = circulatingSupply * (10 ** token.decimals());
        uint256 toMint = finalTotalSupply - currentSupply;
        token.mint(address(this), toMint);

        emit PreFinalization(totalETH, token.balanceOf(address(this)));

        // Setup Uniswap V3 pool
        uint256 contractBalance = token.balanceOf(address(this));
        IWETH(WETH).deposit{value: remainingETH}();
        _safeApprove(
            IERC20(address(WETH)),
            address(nonfungiblePositionManager),
            remainingETH
        );
        _safeApprove(
            IERC20(address(token)),
            address(nonfungiblePositionManager),
            contractBalance
        );

        emit PostWETHDeposit(WETH.balanceOf(address(this)), remainingETH);

        uint256 wethBalance = WETH.balanceOf(address(this));
        require(wethBalance > 0, "No WETH to provide");

        // Initialize pool
        (address token0, address token1) = _sortTokens(
            address(WETH),
            address(token)
        );
        uint160 sqrtPriceX96 = _calculateSqrtPriceX96(
            token0,
            wethBalance,
            contractBalance
        );

        address pool = nonfungiblePositionManager
            .createAndInitializePoolIfNecessary(
                token0,
                token1,
                100, // 0.01% fee tier
                sqrtPriceX96
            );
        require(pool != address(0), "Failed to init V3 pool");

        // Add liquidity
        _addInitialLiquidity(token0, token1, wethBalance, contractBalance);
    }

    // ============ Math Helper Functions ============

    /**
     * @dev Calculates total cost for minting n tokens
     */
    function _totalCost(uint256 n) internal pure returns (uint256) {
        if (n == 0) return 0;

        uint256 rPowN = _powFixed(RATIO, n);
        uint256 numerator = rPowN - 1e18;
        uint256 denominator = RATIO - 1e18;
        uint256 fraction = FullMath.mulDiv(numerator, 1e18, denominator);
        return FullMath.mulDiv(P0, fraction, 1e18);
    }

    /**
     * @dev Safe fixed-point multiplication
     */
    function _mulFixed(uint256 a, uint256 b) internal pure returns (uint256) {
        require(a == 0 || (a * b) / a == b, "Multiplication overflow");
        uint256 c = FullMath.mulDiv(a, b, 1e18);
        require(c <= type(uint256).max, "Result exceeds uint256");
        return c;
    }

    /**
     * @dev Fixed-point exponentiation by squaring
     */
    function _powFixed(
        uint256 base,
        uint256 exp
    ) internal pure returns (uint256) {
        uint256 result = 1e18;
        uint256 current = base;
        uint256 e = exp;

        while (e > 0) {
            if ((e & 1) == 1) {
                result = _mulFixed(result, current);
            }
            current = _mulFixed(current, current);
            e >>= 1;
        }
        return result;
    }

    /**
     * @dev Square root function using binary search and Newton's method
     */
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 xx = x;
        uint256 r = 1;

        // Binary search for the square root
        if (xx >= 0x100000000000000000000000000000000) {
            xx >>= 128;
            r <<= 64;
        }
        if (xx >= 0x10000000000000000) {
            xx >>= 64;
            r <<= 32;
        }
        if (xx >= 0x100000000) {
            xx >>= 32;
            r <<= 16;
        }
        if (xx >= 0x10000) {
            xx >>= 16;
            r <<= 8;
        }
        if (xx >= 0x100) {
            xx >>= 8;
            r <<= 4;
        }
        if (xx >= 0x10) {
            xx >>= 4;
            r <<= 2;
        }
        if (xx >= 0x4) {
            xx >>= 2;
            r <<= 1;
        }

        // Newton's method for higher precision
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;

        uint256 r1 = x / r;
        return (r < r1 ? r : r1);
    }

    // ============ Uniswap Helper Functions ============

    /**
     * @dev Safely approves tokens for Uniswap interactions
     */
    function _safeApprove(
        IERC20 _token,
        address spender,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = address(_token).call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, 0)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "Approve reset failed"
        );

        (success, data) = address(_token).call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, amount)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "Approve failed"
        );
    }

    /**
     * @dev Returns sorted token addresses for Uniswap V3 pool creation
     */
    function _sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
    }

    /**
     * @dev Calculates the sqrt price for Uniswap V3 pool initialization
     */
    function _calculateSqrtPriceX96(
        address token0,
        uint256 wethBalance,
        uint256 tokenBalance
    ) internal view returns (uint160) {
        uint256 finalPrice = getBuyPrice(circulatingSupply, 1);
        // finalPrice is "wei per token" (ETH per token, scaled 1e18)

        // 2**96
        uint256 Q96 = 1 << 96;
        uint256 ratio;
        uint256 sqrtPrice;

        if (token0 == address(WETH)) {
            // Need "token per WETH" = 1 / (ETH per token)
            // finalPrice is scaled by 1e18, so do:
            // ratio = (1e18 * 1e18) / finalPrice = 1e36 / finalPrice,
            // then we scale by 1e-18 eventually in sqrt.  You can do
            // the multiplication/division as you prefer, but the key is to invert.

            // The easiest to read might be:
            ratio = (1e18 * Q96 * Q96) / finalPrice;

            sqrtPrice = _sqrt(ratio);
        } else {
            // WETH is token1, so ratio = (ETH per token) = finalPrice
            // but again we do finalPrice * Q96^2 / 1e18
            ratio = (finalPrice * Q96 * Q96) / 1e18;

            sqrtPrice = _sqrt(ratio);
        }

        return uint160(sqrtPrice);
    }

    /**
     * @dev Encodes the price as a sqrt price for Uniswap V3
     */
    function encodePriceSqrt(
        uint256 amount1,
        uint256 amount0
    ) internal pure returns (uint160) {
        uint256 ratioX192 = (amount1 << 192) / amount0;
        return uint160(_sqrt(ratioX192));
    }

    /**
     * @dev Adds initial liquidity to the Uniswap V3 pool
     */
    function _addInitialLiquidity(
        address token0,
        address token1,
        uint256 wethBalance,
        uint256 tokenBalance
    ) internal {
        uint256 amount0Desired = (token0 == address(token))
            ? tokenBalance
            : wethBalance;
        uint256 amount1Desired = (token1 == address(token))
            ? tokenBalance
            : wethBalance;

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
            .MintParams({
                token0: token0,
                token1: token1,
                fee: 100, // 0.01% fee tier
                tickLower: -887272, // Full range
                tickUpper: 887272, // Full range
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: protocolFeeRecipient,
                deadline: block.timestamp
            });

        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = nonfungiblePositionManager.mint(params);

        emit Finalized(
            tokenId,
            netETHRaised,
            amount0,
            amount1,
            uint256(liquidity)
        );

        // Handle leftovers after liquidity provision
        uint256 leftoverToken = token0 == address(token)
            ? amount0Desired - amount0
            : amount1Desired - amount1;

        uint256 leftoverWETH = token0 == address(WETH)
            ? amount0Desired - amount0
            : amount1Desired - amount1;

        // Burn leftover tokens if any
        if (leftoverToken > 0) {
            token.burn(address(this), leftoverToken);
        }

        // Unwrap and transfer leftover WETH as ETH to fee recipient if any
        if (leftoverWETH > 0) {
            WETH.withdraw(leftoverWETH);
            (bool success, ) = protocolFeeRecipient.call{value: leftoverWETH}(
                ""
            );
            require(success, "ETH transfer failed");
        }
    }

    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {}
}
