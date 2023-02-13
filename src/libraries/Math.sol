// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

/**
 * @title Math library
 * @author Trader Joe
 * @notice This library is used to perform mathematical operations.
 */
library Math {
    /**
     * @dev Returns the max of two numbers.
     * @param a The first number.
     * @param b The second number.
     * @return The max of the two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the min of two numbers.
     * @param a The first number.
     * @param b The second number.
     * @return The min of the two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
