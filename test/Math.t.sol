// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../src/libraries/Math.sol";

contract TestMath is Test {
    using Math for uint256;

    function testFuzz_Min(uint256 a, uint256 b) external {
        uint256 expected = a < b ? a : b;
        uint256 actual = a.min(b);
        assertEq(actual, expected, "testFuzz_Min::1");
    }

    function testFuzz_Max(uint256 a, uint256 b) external {
        uint256 expected = a > b ? a : b;
        uint256 actual = b.max(a);
        assertEq(actual, expected, "testFuzz_Max::1");
    }
}
