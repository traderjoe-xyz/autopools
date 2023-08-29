// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./TestHelper.sol";

import "joe-v2/libraries/math/Uint256x256Math.sol";

contract CustomOracleVaultTest is TestHelper {
    using Uint256x256Math for uint256;

    IAggregatorV3 dfX;
    IAggregatorV3 dfY;

    function setUp() public override {
        super.setUp();

        dfX = new MockAggregator();
        dfY = new MockAggregator();

        MockAggregator(address(dfX)).setPrice(20e18);
        MockAggregator(address(dfY)).setPrice(1e8);

        MockAggregator(address(dfX)).setDecimals(18);
        MockAggregator(address(dfY)).setDecimals(8);

        vm.startPrank(owner);
        vault = factory.createCustomOracleVault(ILBPair(wavax_usdc_20bp), dfX, dfY);
        strategy = factory.createDefaultStrategy(IBaseVault(vault));
        vm.stopPrank();

        vm.label(vault, "Vault Clone");
        vm.label(strategy, "Strategy Clone");

        vm.prank(address(factory));
        IStrategy(strategy).setPendingAumAnnualFee(0.1e4); // 10%
    }

    function test_revert_initializeTwice() external {
        vm.expectRevert("Initializable: contract is already initialized");
        IOracleVault(vault).initialize("", "");
    }

    function test_GetOraclePrice() external {
        assertEq(address(IOracleVault(vault).getOracleX()), address(dfX), "test_GetOraclePrice::1");
        assertEq(address(IOracleVault(vault).getOracleY()), address(dfY), "test_GetOraclePrice::2");

        assertEq(IOracleVault(vault).getPrice(), (uint256(20e6) << 128) / 1e18, "test_GetOraclePrice::3");
    }

    function testFuzz_revert_GetOraclePriceNegative(int256 priceX, int256 priceY) external {
        vm.assume(priceX <= 0 && priceY <= 0);

        MockAggregator(address(dfX)).setPrice(priceX);
        MockAggregator(address(dfY)).setPrice(1);

        vm.expectRevert(IOracleVault.OracleVault__InvalidPrice.selector);
        IOracleVault(vault).getPrice();

        MockAggregator(address(dfX)).setPrice(1);
        MockAggregator(address(dfY)).setPrice(priceY);

        vm.expectRevert(IOracleVault.OracleVault__InvalidPrice.selector);
        IOracleVault(vault).getPrice();
    }

    function testFuzz_revert_GetOraclePriceTooBig(int256 priceX, int256 priceY) external {
        vm.assume(priceX > int256(uint256(type(uint128).max)) && priceY > int256(uint256(type(uint128).max)));

        MockAggregator(address(dfX)).setPrice(priceX);
        MockAggregator(address(dfY)).setPrice(1);

        vm.expectRevert(IOracleVault.OracleVault__InvalidPrice.selector);
        IOracleVault(vault).getPrice();

        MockAggregator(address(dfX)).setPrice(1);
        MockAggregator(address(dfY)).setPrice(priceY);

        vm.expectRevert(IOracleVault.OracleVault__InvalidPrice.selector);
        IOracleVault(vault).getPrice();
    }

    function test_GetImmutableData() external {
        assertEq(address(IOracleVault(vault).getPair()), wavax_usdc_20bp, "test_GetImmutableData::1");
        assertEq(address(IOracleVault(vault).getTokenX()), wavax, "test_GetImmutableData::2");
        assertEq(address(IOracleVault(vault).getTokenY()), usdc, "test_GetImmutableData::3");
    }
}
