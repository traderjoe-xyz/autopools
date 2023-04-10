// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "joe-v2/libraries/math/LiquidityConfigurations.sol";

import "./TestHelper.sol";

contract VaultAndStrategyTest is TestHelper {
    IAggregatorV3 dfX;
    IAggregatorV3 dfY;

    function setUp() public override {
        super.setUp();

        dfX = new MockAggregator();
        dfY = new MockAggregator();

        vm.prank(owner);
        (vault, strategy) = factory.createOracleVaultAndDefaultStrategy(ILBPair(wavax_usdc_20bp), dfX, dfY);
    }

    function test_DepositToVault() external {
        (uint256 shares, uint256 x, uint256 y) = IOracleVault(vault).previewShares(1e18, 1e6);

        assertEq(x, 1e18, "test_DepositToVault::1");
        assertEq(y, 1e6, "test_DepositToVault::2");

        depositToVault(vault, alice, 1e18, 1e6);

        assertEq(IERC20Upgradeable(wavax).balanceOf(strategy), 1e18, "test_DepositToVault::3");
        assertEq(IERC20Upgradeable(usdc).balanceOf(strategy), 1e6, "test_DepositToVault::4");

        assertEq(IOracleVault(vault).balanceOf(vault), 1e6, "test_DepositToVault::5");
        assertEq(IOracleVault(vault).balanceOf(alice), shares - 1e6, "test_DepositToVault::6");
    }

    function test_DepositToVaultTwice() external {
        depositToVault(vault, alice, 1e18, 1e6);

        (uint256 shares, uint256 x, uint256 y) = IOracleVault(vault).previewShares(1e18, 1e6);

        assertEq(x, 1e18, "test_DepositToVaultTwice::1");
        assertEq(y, 1e6, "test_DepositToVaultTwice::2");

        depositToVault(vault, bob, 1e18, 1e6);

        assertEq(IERC20Upgradeable(wavax).balanceOf(strategy), 2e18, "test_DepositToVaultTwice::3");
        assertEq(IERC20Upgradeable(usdc).balanceOf(strategy), 2e6, "test_DepositToVaultTwice::4");

        assertEq(IOracleVault(vault).balanceOf(bob), shares, "test_DepositToVaultTwice::5");
        assertEq(
            IOracleVault(vault).balanceOf(bob),
            IOracleVault(vault).balanceOf(alice) + 1e6,
            "test_DepositToVaultTwice::6"
        );
    }

    function test_WithdrawFromVaultDirect() external {
        depositToVault(vault, alice, 1e18, 20e6);

        uint256 shares = IOracleVault(vault).balanceOf(alice);

        (uint256 x, uint256 y) = IOracleVault(vault).previewAmounts(shares);

        assertEq(x, 1e18 * shares / (shares + 1e6), "test_WithdrawFromVault::1");
        assertEq(y, 20e6 * shares / (shares + 1e6), "test_WithdrawFromVault::2");

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(shares, alice);

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        vm.prank(alice);
        IOracleVault(vault).redeemQueuedWithdrawal(0, alice);

        assertEq(IERC20Upgradeable(wavax).balanceOf(alice), x, "test_WithdrawFromVault::3");
        assertEq(IERC20Upgradeable(usdc).balanceOf(alice), y, "test_WithdrawFromVault::4");

        assertEq(
            IERC20Upgradeable(wavax).balanceOf(strategy),
            (1e18 * 1e6 - 1) / (shares + 1e6) + 1,
            "test_WithdrawFromVault::5"
        );
        assertEq(
            IERC20Upgradeable(usdc).balanceOf(strategy),
            (20e6 * 1e6 - 1) / (shares + 1e6) + 1,
            "test_WithdrawFromVault::6"
        );

        assertEq(IOracleVault(vault).balanceOf(alice), 0, "test_WithdrawFromVault::7");
    }

    function test_WithdrawFromVaultAfterDepositWithDistributions() external {
        uint256 amountX = 15e18;
        uint256 amountY = 100e6;

        depositToVault(vault, alice, amountX, amountY);
        uint256 shares = IOracleVault(vault).balanceOf(alice);

        uint256 activeId = ILBPair(wavax_usdc_20bp).getActiveId();

        uint256[] memory desiredL = new uint256[](3);
        (desiredL[0], desiredL[1], desiredL[2]) = (20e6, 100e6, 20e6);

        vm.prank(owner);

        IStrategy(strategy).rebalance(0, 2, 0, type(uint24).max, desiredL, 1e18, 1e18);

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(shares, alice);

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        vm.prank(alice);
        IOracleVault(vault).redeemQueuedWithdrawal(0, alice);

        uint256 price = ILBPair(wavax_usdc_20bp).getPriceFromId(uint24(activeId));

        uint256 depositInY = ((price * amountX) >> 128) + amountY;
        uint256 receivedInY =
            ((price * IERC20Upgradeable(wavax).balanceOf(alice)) >> 128) + IERC20Upgradeable(usdc).balanceOf(alice);

        assertApproxEqRel(receivedInY, depositInY, 1e15, "test_WithdrawFromVaultAfterdepositWithDistributions::1");
    }

    function test_DepositAndWithdrawWithFees() external {
        depositToVault(vault, alice, 1e36, 1e36);

        uint256 activeId = ILBPair(wavax_usdc_20bp).getActiveId();

        uint256[] memory desiredL = new uint256[](3);
        (desiredL[0], desiredL[1], desiredL[2]) = (100_000e6, 100_000e6, 100_000e6);

        vm.prank(owner);
        IStrategy(strategy).rebalance(1, 3, 2, type(uint24).max, desiredL, 1e18, 1e18);

        uint256 shares = IOracleVault(vault).balanceOf(alice);

        {
            deal(usdc, bob, 100_000e6);
            vm.prank(bob);
            IERC20Upgradeable(usdc).transfer(wavax_usdc_20bp, 100_000e6);

            ILBPair(wavax_usdc_20bp).swap(false, bob);

            deal(wavax, bob, 10_000e18);

            vm.prank(bob);
            IERC20Upgradeable(wavax).transfer(wavax_usdc_20bp, 10_000e18);

            ILBPair(wavax_usdc_20bp).swap(true, bob);

            deal(usdc, bob, 200_000e6);
            vm.prank(bob);
            IERC20Upgradeable(usdc).transfer(wavax_usdc_20bp, 200_000e6);

            ILBPair(wavax_usdc_20bp).swap(false, bob);
        }

        vm.prank(alice);
        IOracleVault(vault).queueWithdrawal(shares, alice);

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        vm.prank(alice);
        IOracleVault(vault).redeemQueuedWithdrawal(0, alice);

        uint256 price = ILBPair(wavax_usdc_20bp).getPriceFromId(uint24(activeId));

        uint256 depositInY = ((price * 1e18) >> 128) + 1e6;
        uint256 receivedInY =
            ((price * IERC20Upgradeable(wavax).balanceOf(alice)) >> 128) + IERC20Upgradeable(usdc).balanceOf(alice);

        assertGt(receivedInY, depositInY, "test_DepositAndWithdrawWithFees::2");
    }

    function test_DepositAndWithdrawNoActive() external {
        depositToVault(vault, alice, 1e24, 1e18);

        uint256 activeId = ILBPair(wavax_usdc_20bp).getActiveId();

        uint256[] memory desiredL = new uint256[](3);
        (desiredL[0], desiredL[1], desiredL[2]) = (50e6, 200e6, 1000e6);

        vm.prank(owner);
        IStrategy(strategy).rebalance(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, desiredL, 1e18, 1e18
        );

        uint256 shares = IOracleVault(vault).balanceOf(alice);

        vm.prank(alice);
        IOracleVault(vault).queueWithdrawal(shares / 100_000, alice);

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        vm.prank(alice);
        IOracleVault(vault).redeemQueuedWithdrawal(0, alice);

        assertGt(IERC20Upgradeable(wavax).balanceOf(alice), 0, "test_DepositAndWithdrawNoActive::1");
        assertGt(IERC20Upgradeable(usdc).balanceOf(alice), 0, "test_DepositAndWithdrawNoActive::2");
    }

    function test_DepositAndSetStrategy() external {
        depositToVault(vault, alice, 25e18, 400e6);

        uint256 activeId = ILBPair(wavax_usdc_20bp).getActiveId();

        uint256[] memory desiredL = new uint256[](3);
        (desiredL[0], desiredL[1], desiredL[2]) = (100e6, 200e6, 100e6);

        vm.startPrank(owner);
        IStrategy(strategy).rebalance(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, desiredL, 1e18, 1e18
        );

        uint256 shares = IOracleVault(vault).balanceOf(alice);
        (uint256 amountX, uint256 amountY) = IBaseVault(vault).previewAmounts(shares);

        address newStrategy = factory.createDefaultStrategy(IBaseVault(vault));
        factory.linkVaultToStrategy(IBaseVault(vault), newStrategy);
        vm.stopPrank();

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(shares, alice);

        vm.startPrank(owner);
        vm.expectRevert(IBaseVault.BaseVault__OnlyStrategy.selector);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        IStrategy(newStrategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);
        vm.stopPrank();

        vm.prank(alice);
        IBaseVault(vault).redeemQueuedWithdrawal(0, alice);

        assertEq(IERC20Upgradeable(wavax).balanceOf(alice), amountX, "test_DepositAndSetStrategy::1");
        assertEq(IERC20Upgradeable(usdc).balanceOf(alice), amountY, "test_DepositAndSetStrategy::2");
    }

    function test_DepositAndEmergencyWithdraw() external {
        depositToVault(vault, alice, 25e18, 400e6);

        uint256 activeId = ILBPair(wavax_usdc_20bp).getActiveId();

        uint256[] memory desiredL = new uint256[](3);
        (desiredL[0], desiredL[1], desiredL[2]) = (100e6, 200e6, 100e6);

        vm.startPrank(owner);
        IStrategy(strategy).rebalance(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, desiredL, 1e18, 1e18
        );

        (uint256 amountX, uint256 amountY) = IBaseVault(vault).previewAmounts(IOracleVault(vault).balanceOf(alice));

        factory.setEmergencyMode(IBaseVault(vault));
        vm.stopPrank();

        vm.prank(alice);
        IOracleVault(vault).emergencyWithdraw();

        assertEq(IERC20Upgradeable(wavax).balanceOf(alice), amountX, "test_DepositAndEmergencyWithdraw::1");
        assertEq(IERC20Upgradeable(usdc).balanceOf(alice), amountY, "test_DepositAndEmergencyWithdraw::2");
    }

    function test_DepositRedeemBeforeEndOfRound() external {
        depositToVault(vault, alice, 1e18, 20e6);

        uint256 shares = IOracleVault(vault).balanceOf(alice);

        (uint256 x, uint256 y) = IOracleVault(vault).previewAmounts(shares);

        assertEq(x, 1e18 * shares / (shares + 1e6), "test_WithdrawFromVault::1");
        assertEq(y, 20e6 * shares / (shares + 1e6), "test_WithdrawFromVault::2");

        vm.expectRevert(IBaseVault.BaseVault__InvalidRound.selector);
        vm.prank(alice);
        IOracleVault(vault).redeemQueuedWithdrawal(1, alice);

        vm.expectRevert(IBaseVault.BaseVault__InvalidRound.selector);
        vm.prank(alice);
        IOracleVault(vault).redeemQueuedWithdrawal(0, alice);

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(shares, alice);

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        vm.prank(alice);
        IOracleVault(vault).redeemQueuedWithdrawal(0, alice);

        assertEq(IERC20Upgradeable(wavax).balanceOf(alice), x, "test_WithdrawFromVault::3");
        assertEq(IERC20Upgradeable(usdc).balanceOf(alice), y, "test_WithdrawFromVault::4");

        assertEq(
            IERC20Upgradeable(wavax).balanceOf(strategy),
            (1e18 * 1e6 - 1) / (shares + 1e6) + 1,
            "test_WithdrawFromVault::5"
        );
        assertEq(
            IERC20Upgradeable(usdc).balanceOf(strategy),
            (20e6 * 1e6 - 1) / (shares + 1e6) + 1,
            "test_WithdrawFromVault::6"
        );

        assertEq(IOracleVault(vault).balanceOf(alice), 0, "test_WithdrawFromVault::7");
    }
}
