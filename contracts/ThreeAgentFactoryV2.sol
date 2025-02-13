// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ThreeAgentFactoryV1.sol";
import "./BondingCurve.sol";

/**
 * @title ThreeAgentFactoryV2
 * @dev Example factory upgrade that deploys BondingCurveV2 instead of BondingCurve
 */
contract ThreeAgentFactoryV2 is ThreeAgentFactoryV1 {

    event TestUpdateEvent(uint256 value);

    /**
     * @notice Creates a new token and bonding curve pair using BondingCurveV2
     * @param name Name of the token
     * @param symbol Symbol of the token
     * @return tokenAddr Address of the created token
     * @return curveAddr Address of the created bonding curve (V2)
     */
    function createTokenAndCurve(
        string calldata name,
        string calldata symbol
    )
        external
        override
        nonReentrant
        returns (address tokenAddr, address curveAddr)
    {
        // Validate inputs (can remain the same checks or adapt as needed)
        require(
            bytes(name).length > 0 && bytes(name).length <= 32,
            "Invalid name length"
        );
        require(
            bytes(symbol).length > 0 && bytes(symbol).length <= 8,
            "Invalid symbol length"
        );

        // Deploy the new BondingCurveV2
        BondingCurve curve = new BondingCurve(
            address(0), // placeholder token address, updated later
            wethAddress,
            nonfungiblePositionManagerAddress,
            protocolFeeRecipient,
            protocolFeePercent,
            address(this) // pass factory as _factory
        );

        // Deploy the token, pointing it to the new curve address
        CurvedToken token = new CurvedToken(address(curve), name, symbol);

        // Update the token address in the newly deployed curve
        curve.setToken(address(token));

        // Record deployment
        deployments.push(
            DeploymentInfo({
                token: address(token),
                curve: address(curve),
                creator: msg.sender,
                timestamp: block.timestamp
            })
        );

        emit TestUpdateEvent(1);

        emit TokenAndCurveCreated(
            msg.sender,
            address(token),
            address(curve),
            block.timestamp
        );

        return (address(token), address(curve));
    }
}
