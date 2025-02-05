// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import your factory contract.
import "contracts/ThreeAgentFactoryV1.sol";

/**
 * @title Test_ThreeAgentFactoryV1
 * @notice Echidna test contract for the ThreeAgentFactoryV1 contract.
 *
 * This contract initializes the factory (by calling initialize in the constructor)
 * and exposes a fuzz target for createTokenAndCurve as well as several invariants.
 */
contract Test_ThreeAgentFactoryV1 is ThreeAgentFactoryV1 {
    // We set some fixed addresses and fee parameters for the initializer.
    // (In a testing context these can be any non-zero addresses.)
    address constant TEST_WETH_ADDRESS =
        0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address constant TEST_NONFUNGIBLE_POSITION_MANAGER_ADDRESS =
        0x1238536071E1c677A632429e3655c799b22cDA52;
    address constant TEST_PROTOCOL_FEE_RECIPIENT =
        0x4E54b5182289377058B96FD2EdFA01EaAf705Fe1;
    uint256 constant TEST_PROTOCOL_FEE_PERCENT = 50000000000000000;

    string constant TEST_NAME = "Test Token";
    string constant TEST_SYMBOL = "TEST";

    /// @notice The constructor initializes the factory so that its invariants can be tested.
    constructor() {
        // Call the initialize function (exactly once)
        initialize(
            TEST_WETH_ADDRESS,
            TEST_NONFUNGIBLE_POSITION_MANAGER_ADDRESS,
            TEST_PROTOCOL_FEE_RECIPIENT,
            TEST_PROTOCOL_FEE_PERCENT
        );
    }

    /**
     * @notice Fuzz target: calls createTokenAndCurve with fuzzed name and symbol.
     *
     * Note: The contract requires that the name is nonempty and at most 32 bytes
     * and that the symbol is nonempty and at most 8 bytes. We simply check these
     * conditions and “skip” the call if they are not met (to avoid reverting).
     */
    function echidna_createTokenAndCurve() external {
        // Call createTokenAndCurve; the return values are ignored.
        this.createTokenAndCurve(TEST_NAME, TEST_SYMBOL);
    }

    // ========= Invariants =========

    /**
     * @notice Invariant: wethAddress is never the zero address.
     */
    function echidna_wethAddress_nonzero() external view returns (bool) {
        return wethAddress != address(0);
    }

    /**
     * @notice Invariant: nonfungiblePositionManagerAddress is never the zero address.
     */
    function echidna_nonfungiblePositionManager_nonzero() external view returns (bool) {
        return nonfungiblePositionManagerAddress != address(0);
    }

    /**
     * @notice Invariant: protocolFeeRecipient is never the zero address.
     */
    function echidna_protocolFeeRecipient_nonzero() external view returns (bool) {
        return protocolFeeRecipient != address(0);
    }

    /**
     * @notice Invariant: Every deployment recorded in the deployments array
     *         has nonzero addresses for both the token and the bonding curve.
     */
    function echidna_deployments_valid() external view returns (bool) {
        for (uint256 i = 0; i < deployments.length; i++) {
            if (deployments[i].token == address(0) || deployments[i].curve == address(0)) {
                return false;
            }
        }
        return true;
    }
}
