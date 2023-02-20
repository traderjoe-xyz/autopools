// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

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
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e6);

        (uint256 shares, uint256 x, uint256 y) = IOracleVault(vault).previewShares(1e18, 1e6);

        assertEq(x, 1e18, "test_DepositToVault::1");
        assertEq(y, 1e6, "test_DepositToVault::2");

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(x, y);
        vm.stopPrank();

        assertEq(IERC20Upgradeable(wavax).balanceOf(strategy), 1e18, "test_DepositToVault::3");
        assertEq(IERC20Upgradeable(usdc).balanceOf(strategy), 1e6, "test_DepositToVault::4");

        assertEq(IOracleVault(vault).balanceOf(vault), 1e6, "test_DepositToVault::5");
        assertEq(IOracleVault(vault).balanceOf(alice), shares - 1e6, "test_DepositToVault::6");
    }

    function test_DepositToVaultTwice() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e6);

        deal(wavax, bob, 1e18);
        deal(usdc, bob, 1e6);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(1e18, 1e6);
        vm.stopPrank();

        (uint256 shares, uint256 x, uint256 y) = IOracleVault(vault).previewShares(1e18, 1e6);

        assertEq(x, 1e18, "test_DepositToVaultTwice::1");
        assertEq(y, 1e6, "test_DepositToVaultTwice::2");

        vm.startPrank(bob);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(1e18, 1e6);
        vm.stopPrank();

        assertEq(IERC20Upgradeable(wavax).balanceOf(strategy), 2e18, "test_DepositToVaultTwice::3");
        assertEq(IERC20Upgradeable(usdc).balanceOf(strategy), 2e6, "test_DepositToVaultTwice::4");

        assertEq(IOracleVault(vault).balanceOf(bob), shares, "test_DepositToVaultTwice::5");
        assertEq(
            IOracleVault(vault).balanceOf(bob),
            IOracleVault(vault).balanceOf(alice) + 1e6,
            "test_DepositToVaultTwice::6"
        );
    }

    function test_WithdrawFromVault() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e6);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(1e18, 1e6);

        uint256 shares = IOracleVault(vault).balanceOf(alice);

        (uint256 x, uint256 y) = IOracleVault(vault).previewAmounts(shares);

        IOracleVault(vault).withdraw(shares);
        vm.stopPrank();

        // Sub 1 because we minted a tiny amount of shares to the vault to lock them
        assertEq(IERC20Upgradeable(wavax).balanceOf(alice), x, "test_WithdrawFromVault::3");
        assertEq(IERC20Upgradeable(usdc).balanceOf(alice), y, "test_WithdrawFromVault::4");

        assertEq(x, 1e18 - 1, "test_WithdrawFromVault::5");
        assertEq(y, 1e6 - 1, "test_WithdrawFromVault::6");

        assertEq(IERC20Upgradeable(wavax).balanceOf(strategy), 1, "test_WithdrawFromVault::7");
        assertEq(IERC20Upgradeable(usdc).balanceOf(strategy), 1, "test_WithdrawFromVault::8");

        assertEq(IOracleVault(vault).balanceOf(alice), 0, "test_WithdrawFromVault::9");
    }

    function test_WithdrawFromVaultAfterdepositWithDistributionsToLB() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e6);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(1e18, 1e6);
        vm.stopPrank();

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory distX = new uint256[](3);
        (distX[0], distX[1], distX[2]) = (0, 0.5e18, 0.5e18);

        uint256[] memory distY = new uint256[](3);
        (distY[0], distY[1], distY[2]) = (0.5e18, 0.5e18, 0);

        vm.prank(owner);
        IStrategy(strategy).depositWithDistributionsToLB(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, distX, distY, 1e18, 1e18
        );

        uint256 shares = IOracleVault(vault).balanceOf(alice);

        vm.prank(alice);
        IOracleVault(vault).withdraw(shares);

        uint256 price = router.getPriceFromId(ILBPair(wavax_usdc_20bp), uint24(activeId));

        uint256 depositInY = ((price * 1e18) >> 128) + 1e6;
        uint256 receivedInY =
            ((price * IERC20Upgradeable(wavax).balanceOf(alice)) >> 128) + IERC20Upgradeable(usdc).balanceOf(alice);

        assertApproxEqRel(receivedInY, depositInY, 1e15, "test_WithdrawFromVaultAfterdepositWithDistributionsToLB::1");
    }

    function test_DepositAndWithdrawFromLbWithFees() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e6);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(1e18, 1e6);
        vm.stopPrank();

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory distX = new uint256[](3);
        (distX[0], distX[1], distX[2]) = (0, 0.5e18, 0.5e18);

        uint256[] memory distY = new uint256[](3);
        (distY[0], distY[1], distY[2]) = (0.5e18, 0.5e18, 0);

        vm.prank(owner);
        IStrategy(strategy).depositWithDistributionsToLB(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, distX, distY, 1e18, 1e18
        );

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
        IOracleVault(vault).withdraw(shares);

        uint256 price = router.getPriceFromId(ILBPair(wavax_usdc_20bp), uint24(activeId));

        uint256 depositInY = ((price * 1e18) >> 128) + 1e6;
        uint256 receivedInY =
            ((price * IERC20Upgradeable(wavax).balanceOf(alice)) >> 128) + IERC20Upgradeable(usdc).balanceOf(alice);

        assertGt(receivedInY, depositInY, "test_DepositAndWithdrawFromLbWithFees::2");
    }

    function test_DepositAndWithdrawNoActive() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e6);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(1e18, 1e6);
        vm.stopPrank();

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory distX = new uint256[](3);
        (distX[0], distX[1], distX[2]) = (0, 1e15, 1e18 - 1e15);

        uint256[] memory distY = new uint256[](3);
        (distY[0], distY[1], distY[2]) = (1e18, 0, 0);

        vm.prank(owner);
        IStrategy(strategy).depositWithDistributionsToLB(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, distX, distY, 1e18, 1e18
        );

        uint256 shares = IOracleVault(vault).balanceOf(alice);

        vm.prank(alice);
        IOracleVault(vault).withdraw(shares / 100_000);

        assertGt(IERC20Upgradeable(wavax).balanceOf(alice), 0, "test_DepositAndWithdrawNoActive::1");
        assertGt(IERC20Upgradeable(usdc).balanceOf(alice), 0, "test_DepositAndWithdrawNoActive::2");
    }

    function test_DepositAndCollectFees() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e6);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(1e18, 1e6);
        vm.stopPrank();

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory distX = new uint256[](3);
        (distX[0], distX[1], distX[2]) = (0, 0.5e18, 0.5e18);

        uint256[] memory distY = new uint256[](3);
        (distY[0], distY[1], distY[2]) = (0.5e18, 0.5e18, 0);

        vm.startPrank(owner);
        factory.setStrategistFee(IStrategy(strategy), 0.1e4);
        IStrategy(strategy).depositWithDistributionsToLB(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, distX, distY, 1e18, 1e18
        );
        vm.stopPrank();

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

        IStrategy(strategy).collectFees();

        assertGt(IERC20Upgradeable(wavax).balanceOf(strategy), 0, "test_DepositAndCollectFees::1");
        assertGt(IERC20Upgradeable(usdc).balanceOf(strategy), 0, "test_DepositAndCollectFees::2");
    }

    function test_DepositAndSetStrategy() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e6);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(1e18, 1e6);
        vm.stopPrank();

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory distX = new uint256[](3);
        (distX[0], distX[1], distX[2]) = (0, 0.5e18, 0.5e18);

        uint256[] memory distY = new uint256[](3);
        (distY[0], distY[1], distY[2]) = (0.5e18, 0.5e18, 0);

        vm.startPrank(owner);
        IStrategy(strategy).depositWithDistributionsToLB(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, distX, distY, 1e18, 1e18
        );

        address newStrategy = factory.createDefaultStrategy(vault);
        factory.linkVaultToStrategy(vault, newStrategy);
        vm.stopPrank();

        uint256 shares = IOracleVault(vault).balanceOf(alice);

        vm.prank(alice);
        IOracleVault(vault).withdraw(shares);

        assertGt(IERC20Upgradeable(wavax).balanceOf(alice), 0.5e18, "test_DepositAndSetStrategy::1");
        assertGt(IERC20Upgradeable(usdc).balanceOf(alice), 0.5e6, "test_DepositAndSetStrategy::2");
    }

    function test_DepositAndPause() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e6);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, 1e18);
        IERC20Upgradeable(usdc).approve(vault, 1e6);

        IOracleVault(vault).deposit(1e18, 1e6);
        vm.stopPrank();

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory distX = new uint256[](3);
        (distX[0], distX[1], distX[2]) = (0, 0.5e18, 0.5e18);

        uint256[] memory distY = new uint256[](3);
        (distY[0], distY[1], distY[2]) = (0.5e18, 0.5e18, 0);

        vm.startPrank(owner);
        IStrategy(strategy).depositWithDistributionsToLB(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, distX, distY, 1e18, 1e18
        );

        factory.pauseVault(vault);
        vm.stopPrank();

        uint256 shares = IOracleVault(vault).balanceOf(alice);

        vm.prank(alice);
        IOracleVault(vault).withdraw(shares);

        assertGt(IERC20Upgradeable(wavax).balanceOf(alice), 0.5e18, "test_DepositAndPause::1");
        assertGt(IERC20Upgradeable(usdc).balanceOf(alice), 0.5e6, "test_DepositAndPause::2");
    }
}
