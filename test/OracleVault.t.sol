// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./TestHelper.sol";

contract OracleVaultTest is TestHelper {
    IAggregatorV3 dfX;
    IAggregatorV3 dfY;

    function setUp() public override {
        super.setUp();

        dfX = new MockAggregator();
        dfY = new MockAggregator();

        vm.startPrank(owner);
        vault = factory.createOracleVault(ILBPair(wavax_usdc_20bp), dfX, dfY);
        strategy = factory.createDefaultStrategy(vault);

        factory.setStrategistFee(IStrategy(strategy), 0.1e4); // 10%
        vm.stopPrank();
    }

    function test_revert_initializeTwice() external {
        vm.expectRevert("Initializable: contract is already initialized");
        IOracleVault(vault).initialize("", "");
    }

    function test_GetOraclePrice() external {
        assertEq(address(OracleVault(vault).getOracleX()), address(dfX), "test_GetOraclePrice::1");
        assertEq(address(OracleVault(vault).getOracleY()), address(dfY), "test_GetOraclePrice::2");

        assertEq(OracleVault(vault).getPrice(), (uint256(1e18 * 1e6) << 128) / (1e18 * 1e18), "test_GetOraclePrice::3");
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
        assertEq(address(OracleVault(vault).getPair()), wavax_usdc_20bp, "test_GetImmutableData::1");
        assertEq(address(OracleVault(vault).getTokenX()), wavax, "test_GetImmutableData::2");
        assertEq(address(OracleVault(vault).getTokenY()), usdc, "test_GetImmutableData::3");
    }

    function test_Operators() external {
        (address defaultOperator, address operator) = IOracleVault(vault).getOperators();

        assertEq(defaultOperator, owner, "test_Operators::1");
        assertEq(operator, address(0), "test_Operators::2");

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        (defaultOperator, operator) = IOracleVault(vault).getOperators();

        assertEq(defaultOperator, owner, "test_Operators::3");
        assertEq(operator, address(0), "test_Operators::4");

        vm.prank(owner);
        factory.setOperator(IStrategy(strategy), address(1));

        (defaultOperator, operator) = IOracleVault(vault).getOperators();

        assertEq(defaultOperator, owner, "test_Operators::5");
        assertEq(operator, address(1), "test_Operators::6");
    }

    function test_GetStrategy() external {
        assertEq(address(IOracleVault(vault).getStrategy()), address(0), "test_GetStrategy::1");

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        assertEq(address(IOracleVault(vault).getStrategy()), strategy, "test_GetStrategy::2");
    }

    function test_GetStrategistFee() external {
        assertEq(IOracleVault(vault).getStrategistFee(), 0, "test_GetStrategistFee::1");

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        assertEq(IOracleVault(vault).getStrategistFee(), 0.1e4, "test_GetStrategistFee::2");
    }

    function test_GetBalances() external {
        (uint256 x, uint256 y) = IOracleVault(vault).getBalances();

        assertEq(x, 0, "test_GetBalances::1");
        assertEq(y, 0, "test_GetBalances::2");

        deal(wavax, vault, 1e18);
        deal(usdc, vault, 1e18);

        (x, y) = IOracleVault(vault).getBalances();

        assertEq(x, 1e18, "test_GetBalances::3");
        assertEq(y, 1e18, "test_GetBalances::4");

        deal(wavax, strategy, 1e18);
        deal(usdc, strategy, 1e18);

        (x, y) = IOracleVault(vault).getBalances();

        assertEq(x, 1e18, "test_GetBalances::5");
        assertEq(y, 1e18, "test_GetBalances::6");

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        (x, y) = IOracleVault(vault).getBalances();

        assertEq(x, 2e18, "test_GetBalances::7");
        assertEq(y, 2e18, "test_GetBalances::8");

        vm.prank(owner);
        factory.pauseVault(vault);

        (x, y) = IOracleVault(vault).getBalances();

        assertEq(x, 2e18, "test_GetBalances::9");
        assertEq(y, 2e18, "test_GetBalances::10");
    }

    function test_GetRange() external {
        (uint24 low, uint24 upper) = IOracleVault(vault).getRange();

        assertEq(low, 0, "test_GetRange::1");
        assertEq(upper, 0, "test_GetRange::2");

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        (low, upper) = IOracleVault(vault).getRange();

        assertEq(low, 0, "test_GetRange::3");
        assertEq(upper, 0, "test_GetRange::4");
    }

    function test_GetPendingFees() external {
        (uint256 x, uint256 y) = IOracleVault(vault).getPendingFees();

        assertEq(x, 0, "test_GetPendingFees::1");
        assertEq(y, 0, "test_GetPendingFees::2");

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        (x, y) = IOracleVault(vault).getPendingFees();

        assertEq(x, 0, "test_GetPendingFees::3");
        assertEq(y, 0, "test_GetPendingFees::4");
    }

    function testFuzz_PreviewShares(uint128 x, uint128 y) external {
        uint256 price = IOracleVault(vault).getPrice();
        assertEq(price, (uint256(1e18 * 1e6) << 128) / (1e18 * 1e18), "test_PreviewShares::1");

        vm.assume((uint256(y) << 128) <= type(uint256).max - price * x);

        (uint256 shares, uint256 effectiveX, uint256 effectiveY) = IOracleVault(vault).previewShares(x, y);

        assertEq(effectiveX, x, "test_PreviewShares::2");
        assertEq(effectiveY, y, "test_PreviewShares::3");

        assertEq(shares, price * effectiveX + (effectiveY << 128), "test_PreviewShares::4");
    }

    function test_PreviewSharesWithZeroAmounts() external {
        (uint256 shares, uint256 effectiveX, uint256 effectiveY) = IOracleVault(vault).previewShares(0, 0);

        assertEq(effectiveX, 0, "test_PreviewSharesWithZeroAmounts::1");
        assertEq(effectiveY, 0, "test_PreviewSharesWithZeroAmounts::2");

        assertEq(shares, 0, "test_PreviewSharesWithZeroAmounts::3");
    }

    function test_revert_PreviewShares(uint256 x, uint256 y) external {
        uint256 price = IOracleVault(vault).getPrice();
        assertEq(price, (uint256(1e18 * 1e6) << 128) / (1e18 * 1e18), "test_PreviewShares::1");

        vm.assume(y > type(uint128).max || x > type(uint256).max / price || (y << 128) > type(uint256).max - price * x);

        vm.expectRevert(IOracleVault.OracleVault__AmountsOverflow.selector);
        IOracleVault(vault).previewShares(x, y);
    }
}
