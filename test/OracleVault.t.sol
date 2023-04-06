// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./TestHelper.sol";

import "joe-v2/libraries/math/Uint256x256Math.sol";

contract OracleVaultTest is TestHelper {
    using Uint256x256Math for uint256;

    IAggregatorV3 dfX;
    IAggregatorV3 dfY;

    function setUp() public override {
        super.setUp();

        dfX = new MockAggregator();
        dfY = new MockAggregator();

        MockAggregator(address(dfX)).setPrice(20e8);
        MockAggregator(address(dfY)).setPrice(1e8);

        vm.startPrank(owner);
        vault = factory.createOracleVault(ILBPair(wavax_usdc_20bp), dfX, dfY);
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

    function test_Operators() external {
        (address defaultOperator, address operator) = IOracleVault(vault).getOperators();

        assertEq(defaultOperator, owner, "test_Operators::1");
        assertEq(operator, address(0), "test_Operators::2");

        linkVaultToStrategy(vault, strategy);

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

        linkVaultToStrategy(vault, strategy);

        assertEq(address(IOracleVault(vault).getStrategy()), strategy, "test_GetStrategy::2");
    }

    function test_GetAumAnnualFee() external {
        assertEq(IOracleVault(vault).getAumAnnualFee(), 0, "test_GetAumAnnualFee::1");

        linkVaultToStrategy(vault, strategy);
        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        assertEq(IOracleVault(vault).getAumAnnualFee(), 0.1e4, "test_GetAumAnnualFee::2");
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

        linkVaultToStrategy(vault, strategy);

        (x, y) = IOracleVault(vault).getBalances();

        assertEq(x, 2e18, "test_GetBalances::7");
        assertEq(y, 2e18, "test_GetBalances::8");

        vm.prank(owner);
        factory.setEmergencyMode(IBaseVault(vault));

        (x, y) = IOracleVault(vault).getBalances();

        assertEq(x, 2e18, "test_GetBalances::9");
        assertEq(y, 2e18, "test_GetBalances::10");
    }

    function test_GetRange() external {
        (uint24 low, uint24 upper) = IOracleVault(vault).getRange();

        assertEq(low, 0, "test_GetRange::1");
        assertEq(upper, 0, "test_GetRange::2");

        linkVaultToStrategy(vault, strategy);

        (low, upper) = IOracleVault(vault).getRange();

        assertEq(low, 0, "test_GetRange::3");
        assertEq(upper, 0, "test_GetRange::4");
    }

    function testFuzz_PreviewShares(uint256 priceX, uint256 priceY, uint128 x, uint128 y) external {
        priceX = bound(priceX, 1, type(uint128).max);
        priceY = bound(priceY, 1, type(uint128).max);

        vm.assume(priceX * 1e6 / (priceY * 1e18) > 0);

        MockAggregator(address(dfX)).setPrice(int256(priceX));
        MockAggregator(address(dfY)).setPrice(int256(priceY));

        uint256 price = IOracleVault(vault).getPrice();

        (uint256 shares, uint256 effectiveX, uint256 effectiveY) = IOracleVault(vault).previewShares(x, y);

        assertEq(effectiveX, x, "test_PreviewShares::2");
        assertEq(effectiveY, y, "test_PreviewShares::3");

        assertEq(shares, (price.mulShiftRoundDown(effectiveX, 128) + y) * 1e6, "test_PreviewShares::4");
    }

    function test_PreviewSharesWithZeroAmounts() external {
        (uint256 shares, uint256 effectiveX, uint256 effectiveY) = IOracleVault(vault).previewShares(0, 0);

        assertEq(effectiveX, 0, "test_PreviewSharesWithZeroAmounts::1");
        assertEq(effectiveY, 0, "test_PreviewSharesWithZeroAmounts::2");

        assertEq(shares, 0, "test_PreviewSharesWithZeroAmounts::3");
    }

    function testFuzz_revert_PreviewShares(uint256 priceX, uint256 priceY, uint256 x, uint256 y) external {
        priceX = bound(priceX, 1, type(uint128).max);
        priceY = bound(priceY, 1, type(uint128).max);

        vm.assume(priceX * 1e6 / (priceY * 1e18) > 0);

        MockAggregator(address(dfX)).setPrice(int256(priceX));
        MockAggregator(address(dfY)).setPrice(int256(priceY));

        uint256 price = IOracleVault(vault).getPrice();

        x = bound(x, type(uint256).max / (price == 0 ? 1 : price), type(uint256).max);
        y = bound(y, type(uint256).max - type(uint256).max / (price == 0 ? 1 : price) + 1, type(uint256).max);

        vm.expectRevert();
        IOracleVault(vault).previewShares(x, y);
    }

    function test_revert_GetPrice() external {
        MockAggregator(address(dfX)).setPrice(1);
        MockAggregator(address(dfY)).setPrice((1 << 128) + 1);

        vm.expectRevert(IOracleVault.OracleVault__InvalidPrice.selector);
        IOracleVault(vault).getPrice();
    }

    function testFuzz_PreviewSharesAfterDeposit(uint256 priceX, uint256 priceY, uint128 x, uint128 y) external {
        priceX = bound(priceX, 1, type(uint128).max);
        priceY = bound(priceY, 1, type(uint128).max);

        vm.assume(priceX * 1e6 / (priceY * 1e18) > 0);

        MockAggregator(address(dfX)).setPrice(int256(priceX));
        MockAggregator(address(dfY)).setPrice(int256(priceY));

        linkVaultToStrategy(vault, strategy);
        depositToVault(vault, alice, 1e18, 20e6);

        uint256 price = IOracleVault(vault).getPrice();

        (uint256 shares, uint256 effectiveX, uint256 effectiveY) = IOracleVault(vault).previewShares(x, y);

        assertEq(effectiveX, x, "test_PreviewShares::2");
        assertEq(effectiveY, y, "test_PreviewShares::3");

        assertEq(shares, (price.mulShiftRoundDown(effectiveX, 128) + y) * 1e6, "test_PreviewShares::4");
    }
}
