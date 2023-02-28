// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../src/libraries/Distribution.sol";

contract DistributionTest is Test {
    using Distribution for uint256[];

    function testFuzz_ComputeDistribution(uint256[] memory amounts) external {
        uint256[] memory distribution = new uint256[](amounts.length);

        uint256 sum;
        for (uint256 i; i < amounts.length; ++i) {
            vm.assume(amounts[i] < type(uint256).max - sum && amounts[i] < type(uint256).max / 1e18);
            distribution[i] = amounts[i];
            sum += amounts[i];
        }

        distribution.computeDistribution(sum, 0, amounts.length);

        for (uint256 i; i < distribution.length; ++i) {
            if (sum != 0) assertEq(distribution[i], amounts[i] * 1e18 / sum, "testFuzz_ComputeDistribution::1");
            else assertEq(distribution[i], 0, "testFuzz_ComputeDistribution::2");
        }
    }

    function testFuzz_ComputeDistributionX(uint128[] memory amounts, uint256 price) external {
        vm.assume(price > 0);

        uint256[] memory desiredL;

        assembly {
            desiredL := amounts
        }

        uint256[] memory expectedDistributionX = new uint256[](desiredL.length);

        uint256 sum;
        for (uint256 i; i < desiredL.length; ++i) {
            vm.assume(desiredL[i] <= type(uint128).max && (desiredL[i] << 128) / price <= type(uint128).max);

            expectedDistributionX[i] = (desiredL[i] << 128) / price;
            sum += expectedDistributionX[i];
        }

        uint256[] memory distributionX = new uint256[](desiredL.length);

        desiredL.computeDistributionX(distributionX, price, 0, 0, false);

        for (uint256 i; i < desiredL.length; ++i) {
            if (sum != 0) {
                assertEq(distributionX[i], expectedDistributionX[i] * 1e18 / sum, "test_ComputeDistributionX::1");
            } else {
                assertEq(distributionX[i], 0, "test_ComputeDistributionX::2");
            }
        }
    }

    function testFuzz_ComputeDistributionY(uint128[] memory amounts) external {
        uint256[] memory desiredL;

        assembly {
            desiredL := amounts
        }

        uint256[] memory expectedDistributionY = new uint256[](desiredL.length);

        uint256 sum;
        for (uint256 i; i < desiredL.length; ++i) {
            vm.assume(desiredL[i] <= type(uint128).max);

            expectedDistributionY[i] = desiredL[i];
            sum += expectedDistributionY[i];
        }

        uint256[] memory distributionY = new uint256[](desiredL.length);

        desiredL.computeDistributionY(distributionY, 0, distributionY.length, false);

        for (uint256 i; i < desiredL.length; ++i) {
            if (sum != 0) {
                assertEq(distributionY[i], expectedDistributionY[i] * 1e18 / sum, "test_ComputeDistributionY::1");
            } else {
                assertEq(distributionY[i], 0, "test_ComputeDistributionY::2");
            }
        }
    }

    function test_GetDistributions() external {
        uint256[] memory amounts = new uint256[](3);
        (amounts[0], amounts[1], amounts[2]) = (1000e6, 1000e6, 1000e6);

        uint256 price = (uint256(1000e6) << 128) / 1e18;
        uint256 compositionFactor = (uint256(0.5e18) << 128) / 1e18;

        (uint256 amountX, uint256 amountY, uint256[] memory distributionX, uint256[] memory distributionY) =
            amounts.getDistributions(compositionFactor, price, 1);

        assertEq(amountX, 1.5e18, "test_GetDistributions::1");
        assertEq(amountY, 1500e6, "test_GetDistributions::2");

        uint256 oneThird = uint256(1e18) / 3;

        assertEq(distributionX[0], 0, "test_GetDistributions::3");
        assertEq(distributionX[1], oneThird, "test_GetDistributions::4");
        assertEq(distributionX[2], oneThird * 2, "test_GetDistributions::5");

        assertEq(distributionY[0], oneThird * 2, "test_GetDistributions::6");
        assertEq(distributionY[1], oneThird, "test_GetDistributions::7");
        assertEq(distributionY[2], 0, "test_GetDistributions::8");
    }

    function testFuzz_GetDistributions(
        uint128 compositionFactor,
        uint128[] memory amounts,
        uint256 price,
        uint256 index
    ) external {
        vm.assume(compositionFactor <= 1 << 128 && index < amounts.length && price > 0);

        uint256[] memory desiredL;

        assembly {
            desiredL := amounts
        }

        for (uint256 i = 0; i < desiredL.length; i++) {
            vm.assume((desiredL[i] << 128) / price <= type(uint128).max);
        }

        (uint256 amountX, uint256 amountY, uint256[] memory distributionX, uint256[] memory distributionY) =
            desiredL.getDistributions(compositionFactor, price, index);

        {
            (uint256 sumDX, uint256 sumDY) = (0, 0);
            for (uint256 i = 0; i < desiredL.length; i++) {
                uint256 x = amountX * distributionX[i] / 1e18;
                uint256 y = amountY * distributionY[i] / 1e18;

                sumDX += distributionX[i];
                sumDY += distributionY[i];

                assertLe((x * price >> 128) + y, desiredL[i], "testFuzz_GetDistributions::1");
            }

            assertLe(sumDX, 1e18, "testFuzz_GetDistributions::2");
            assertLe(sumDY, 1e18, "testFuzz_GetDistributions::3");
        }

        uint256[] memory expectedDX = new uint256[](desiredL.length);
        uint256[] memory expectedDY = new uint256[](desiredL.length);

        uint256 activeAmount = desiredL[index];

        uint256 sumY = (activeAmount * compositionFactor) >> 128;
        uint256 sumX = ((activeAmount - sumY) << 128) / price;

        expectedDY[index] = sumY;
        expectedDX[index] = sumX;

        for (uint256 i = 0; i < desiredL.length; i++) {
            if (i < index) {
                expectedDY[i] = desiredL[i];
                sumY += expectedDY[i];
            } else if (i > index) {
                expectedDX[i] = (uint256(desiredL[i]) << 128) / price;
                sumX += expectedDX[i];
            }
        }

        for (uint256 i = 0; i < desiredL.length; i++) {
            if (sumX > 0) expectedDX[i] = expectedDX[i] * 1e18 / sumX;
            if (sumY > 0) expectedDY[i] = expectedDY[i] * 1e18 / sumY;

            assertEq(
                distributionX[i],
                expectedDX[i],
                string(abi.encodePacked("testFuzz_GetDistributions::4-", vm.toString(i)))
            );
            assertEq(
                distributionY[i],
                expectedDY[i],
                string(abi.encodePacked("testFuzz_GetDistributions::5-", vm.toString(i)))
            );
        }
    }
}
