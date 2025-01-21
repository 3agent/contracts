// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/FullMath.sol";

contract MockFullMath {
    function testMultiplyDivide(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) public pure returns (uint256) {
        return FullMath.mulDiv(a, b, denominator);
    }

    function testMultiplyDivideRoundUp(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) public pure returns (uint256) {
        return FullMath.mulDivRoundingUp(a, b, denominator);
    }
}