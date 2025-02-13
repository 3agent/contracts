// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../BondingCurve.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/INonfungiblePositionManager.sol";

/*//////////////////////////////////////////////////////////////
                      DUMMY CONTRACTS
//////////////////////////////////////////////////////////////*/

/// @dev A minimal ERC20 token with mint and burn.
contract DummyToken {
    // Public variables (name, symbol, decimals) so that BondingCurve can call token.decimals()
    string public name = "Dummy Token";
    string public symbol = "DUM";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice Mint tokens to an address.
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    /// @notice Burn tokens from an address.
    function burn(address from, uint256 amount) external {
        require(
            balanceOf[from] >= amount,
            "DummyToken: burn amount exceeds balance"
        );
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }

    /// @notice Standard transferFrom.
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        require(
            balanceOf[sender] >= amount,
            "DummyToken: insufficient balance"
        );
        require(
            allowance[sender][msg.sender] >= amount,
            "DummyToken: allowance too low"
        );
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    /// @notice Standard approve.
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    /// @notice Standard transfer.
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool) {
        require(
            balanceOf[msg.sender] >= amount,
            "DummyToken: insufficient balance"
        );
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

/// @dev A minimal "WETH" contract that implements deposit/withdraw and ERC20 methods.
contract DummyWETH is IWETH {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    function totalSupply() external view override returns (uint256) {
        return address(this).balance;
    }

    /// @notice Deposit ETH to get WETH.
    function deposit() external payable override {
        balanceOf[msg.sender] += msg.value;
    }

    /// @notice Withdraw WETH to get ETH.
    function withdraw(uint256 amount) external override {
        require(
            balanceOf[msg.sender] >= amount,
            "DummyWETH: insufficient balance"
        );
        balanceOf[msg.sender] -= amount;
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "DummyWETH: ETH transfer failed");
    }

    /// @notice Standard approve.
    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    /// @notice Standard transferFrom.
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        require(balanceOf[sender] >= amount, "DummyWETH: insufficient balance");
        require(
            allowance[sender][msg.sender] >= amount,
            "DummyWETH: allowance too low"
        );
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    /// @notice Standard transfer.
    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        require(
            balanceOf[msg.sender] >= amount,
            "DummyWETH: insufficient balance"
        );
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

/// @dev A dummy Uniswap V3 position manager.
contract DummyNPM is INonfungiblePositionManager {
    /// @notice Simply return a nonzero "pool" address.
    function createAndInitializePoolIfNecessary(
        address,  // token0
        address,  // token1
        uint24,   // fee
        uint160   // sqrtPriceX96
    ) external payable override returns (address pool) {
        // For testing we simply return a dummy pool address.
        return address(0x1);
    }

    /// @notice Dummy mint that "succeeds" and returns fixed values.
    function mint(
        MintParams calldata params
    )
        external
        payable
        override
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        tokenId = 1;
        liquidity = 1000;
        // For testing, we assume the full desired amounts are "used."
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
    }

    function collect(
        CollectParams calldata params
    ) external payable override returns (uint256 amount0, uint256 amount1) {
        // Do nothing.
    }

    function positions(
        uint256 tokenId
    )
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        // do nothing
    }

    function approve(address, uint256) external override {
        // Do nothing.
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external override {
        // Do nothing.
    }

    function safeTransferFrom(
        address,  // from
        address,  // to
        uint256,  // tokenId
        bytes calldata  // data
    ) external override {
        // Do nothing.
    }
}

/*//////////////////////////////////////////////////////////////
               ECHIDNA TEST CONTRACT
//////////////////////////////////////////////////////////////*/

contract Test_BondingCurve {
    // Instance of the bonding curve under test.
    BondingCurve public curve;
    // Our dummy token that the bonding curve uses.
    DummyToken public token;
    // Our dummy WETH contract.
    DummyWETH public weth;
    // Our dummy Uniswap V3 position manager.
    DummyNPM public npm;

    // In our tests we make this contract the fee recipient and the factory.
    address public protocolFeeRecipient = address(this);
    address public factory = address(this);
    // Example protocol fee: 1% (scaled by 1e18, so 1e16)
    uint256 public protocolFeePercent = 1e16;

    //-------------------------------------------------------------------------
    // CONSTRUCTOR
    //-------------------------------------------------------------------------

    constructor() payable {
        // Deploy our dummy contracts.
        token = new DummyToken();
        weth = new DummyWETH();
        npm = new DummyNPM();

        // Deploy the BondingCurve contract with the dummy dependencies.
        curve = new BondingCurve(
            address(token),
            address(weth),
            address(npm),
            protocolFeeRecipient,
            protocolFeePercent,
            factory
        );
    }

    // Allow this contract to receive ETH (for WETH deposit and refunds).
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                        PUBLIC ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fuzzable function to buy tokens.
    /// The function reads the current cost for the given amount
    /// and calls buy only if the provided msg.value is high enough.
    function buy(uint256 amount) public payable {
        // Do nothing if the bonding curve has already finalized.
        if (curve.finalized()) return;

        // Get the current cost to buy `amount` tokens.
        (uint256 cost, ) = curve.getBuyPrice(curve.circulatingSupply(), amount);
        // Only proceed if enough ETH was sent.
        if (msg.value < cost) return;

        // Call the buy function sending exactly `cost`.
        // (Any extra ETH will be refunded by the contract.)
        curve.buy{value: cost}(amount);
    }

    /// @notice Fuzzable function to sell tokens.
    /// (This function will only work if this contract holds tokens.)
    function sell(uint256 amount) public {
        // Do nothing if finalized.
        if (curve.finalized()) return;

        // Compute the scaled (ERC20) amount.
        uint256 scaledAmount = amount * (10 ** token.decimals());
        // Only sell if this contract holds enough tokens.
        if (token.balanceOf(address(this)) < scaledAmount) return;

        // Approve the bonding curve contract to pull the tokens.
        token.approve(address(curve), scaledAmount);
        curve.sell(amount);
    }

    /// @notice Fuzzable function that attempts to "push" the curve to finalization
    /// by buying tokens. (Finalization happens automatically when netETHRaised >= CAP.)
    function buyToFinalize(uint256 amount) public payable {
        if (curve.finalized()) return;
        (uint256 cost, ) = curve.getBuyPrice(curve.circulatingSupply(), amount);
        if (msg.value < cost) return;
        curve.buy{value: cost}(amount);
    }

    /// @notice This fuzzable function attempts to buy tokens and uses assertions to check state changes.
    /// The function will only buy if the curve has not finalized and the amount is positive.
    function buyWithAssertions(uint256 amount) public payable {
        if (curve.finalized()) return;
        (uint256 cost, ) = curve.getBuyPrice(curve.circulatingSupply(), amount);
        // Assert that the cost is nonzero for nonzero token amounts.
        if (amount > 0) {
            assert(cost > 0);
        }
        if (msg.value < cost) return;
        uint256 oldSupply = curve.circulatingSupply();
        uint256 oldNetETH = curve.netETHRaised();
        curve.buy{value: cost}(amount);
        // Assert that the state has been updated appropriately.
        assert(curve.circulatingSupply() == oldSupply + amount);

        // Assert that the netETHRaised has increased by the cost of the purchase.
        assert(curve.netETHRaised() == oldNetETH + cost);
    }

    /// @notice This fuzzable function attempts to sell tokens and uses assertions to check state changes.
    /// The function will only sell if there are tokens to sell.
    function sellWithAssertions(uint256 amount) public {
        // Do nothing if the curve is finalized or if amount is zero.
        if (curve.finalized() || amount == 0) return;

        uint256 currentSupply = curve.circulatingSupply();
        // Ensure we do not try to sell more than the current circulating supply.
        if (amount > currentSupply) return;

        // Calculate the token amount in ERC20 decimals.
        uint256 scaledAmount = amount * (10 ** token.decimals());
        // If the caller (this contract) doesn't have enough tokens, skip.
        if (token.balanceOf(address(this)) < scaledAmount) return;

        // Record state variables before the sale.
        uint256 oldSupply = currentSupply;
        uint256 oldTotalSupply = token.totalSupply();

        // Approve the curve contract to spend our tokens.
        token.approve(address(curve), scaledAmount);

        curve.sell(amount);

        // Assert that circulatingSupply has decreased by the amount sold.
        assert(curve.circulatingSupply() == oldSupply - amount);

        // Assert that the total token supply has decreased by the scaled amount (tokens burned).
        assert(token.totalSupply() == oldTotalSupply - scaledAmount);
    }

    /// @notice Verify protocol fee calculation during finalization
    function testProtocolFee(uint256 amount) public payable {
        uint256 initialBalance = protocolFeeRecipient.balance;
        // Buy tokens to reach CAP
        (uint256 cost, ) = curve.getBuyPrice(curve.circulatingSupply(), amount);
        curve.buy{value: cost}(amount);

        if (curve.finalized()) {
            uint256 expectedFee = (cost * protocolFeePercent) / 1e18;
            assert(
                protocolFeeRecipient.balance == initialBalance + expectedFee
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// Invariant: For any given supply, buying 2 tokens should cost at least as much as buying 1 token.
    function echidna_buyPrice_monotonic() public view returns (bool) {
        uint256 supply = curve.circulatingSupply();
        (uint256 price1, ) = curve.getBuyPrice(supply, 1);
        (uint256 price2, ) = curve.getBuyPrice(supply, 2);
        return price2 >= price1;
    }

    /// Invariant: If there is enough circulating supply, selling 2 tokens should refund at least as much as selling 1.
    function echidna_sellPrice_monotonic() public view returns (bool) {
        uint256 supply = curve.circulatingSupply();
        // Only check when there are at least 2 tokens in circulation.
        if (supply < 2) return true;
        uint256 refund1 = curve.getSellPrice(supply, 1);
        uint256 refund2 = curve.getSellPrice(supply, 2);
        return refund2 >= refund1;
    }

    /// Invariant: Until finalization, netETHRaised is below the cap.
    function echidna_netETH_less_than_CAP() public view returns (bool) {
        if (curve.finalized()) return true;
        return curve.netETHRaised() < curve.CAP();
    }

    /// Invariant: Once finalized, the netETHRaised is at least the cap.
    function echidna_finalized_implies_cap_reached()
        public
        view
        returns (bool)
    {
        if (curve.finalized()) return curve.netETHRaised() >= curve.CAP();
        return true;
    }

    /// Invariant: The token total supply is consistent with circulatingSupply.
    /// (Before finalization: minted tokens equal circulatingSupply * 10^decimals;
    ///  after finalization: total supply equals 1,000,000,000 tokens (scaled by 1e18).)
    function echidna_token_total_supply_correct() public view returns (bool) {
        if (curve.finalized()) {
            return token.totalSupply() == 1_000_000_000 * (10 ** 18);
        } else {
            return
                token.totalSupply() ==
                curve.circulatingSupply() * (10 ** token.decimals());
        }
    }

    /// Invariant: Buying exactly CAP amount of tokens triggers finalization
    function echidna_buy_cap_finalizes() public view returns (bool) {
        if (curve.netETHRaised() == curve.CAP()) {
            return curve.finalized();
        }
        return true;
    }

    /// Invariant: Can't sell more tokens than in circulation
    function echidna_sell_exceeds_supply() public returns (bool) {
        uint256 supply = curve.circulatingSupply();
        if (supply == 0) return true;
        uint256 sellAmount = supply + 1;
        try curve.sell(sellAmount) {
            return false;
        } catch {
            return true;
        }
    }

    /// Invariant: Price increases with supply
    function echidna_price_increases_with_supply() public view returns (bool) {
        uint256 supply = curve.circulatingSupply();
        if (supply == 0) return true;
        (uint256 priceAtCurrentSupply, ) = curve.getBuyPrice(supply, 1);
        (uint256 priceAtHigherSupply, ) = curve.getBuyPrice(supply + 1, 1);
        return priceAtHigherSupply > priceAtCurrentSupply;
    }

    /// Invariant: Buy price should be higher than sell price for same amount
    function echidna_buy_price_exceeds_sell_price() public view returns (bool) {
        uint256 supply = curve.circulatingSupply();
        if (supply == 0) return true;
        uint256 amount = 1;
        (uint256 buyPrice, ) = curve.getBuyPrice(supply, amount);
        uint256 sellPrice = curve.getSellPrice(supply, amount);
        return buyPrice > sellPrice;
    }

    /// Invariant: Finalization adds liquidity to Uniswap (with dust tolerance)
    function echidna_finalization_adds_liquidity() public view returns (bool) {
        if (!curve.finalized()) return true;
        // Check approvals were made to NPM
        assert(weth.allowance(address(curve), address(npm)) > 0);
        assert(token.allowance(address(curve), address(npm)) > 0);
        return true;
    }
}
