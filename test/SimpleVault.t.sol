// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./TestHelper.sol";

contract SimpleVaultTest is TestHelper {
    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        vault = factory.createSimpleVault(ILBPair(wavax_usdc_20bp));
        strategy = factory.createDefaultStrategy(vault);

        factory.setStrategistFee(IStrategy(strategy), 0.1e4); // 10%
        vm.stopPrank();
    }

    function test_revert_initializeTwice() external {
        vm.expectRevert("Initializable: contract is already initialized");
        ISimpleVault(vault).initialize("", "");
    }

    function test_GetImmutableData() external {
        assertEq(address(SimpleVault(vault).getPair()), wavax_usdc_20bp, "test_GetImmutableData::1");
        assertEq(address(SimpleVault(vault).getTokenX()), wavax, "test_GetImmutableData::2");
        assertEq(address(SimpleVault(vault).getTokenY()), usdc, "test_GetImmutableData::3");
    }

    function test_Operators() external {
        (address defaultOperator, address operator) = ISimpleVault(vault).getOperators();

        assertEq(defaultOperator, owner, "test_Operators::1");
        assertEq(operator, address(0), "test_Operators::2");

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        (defaultOperator, operator) = ISimpleVault(vault).getOperators();

        assertEq(defaultOperator, owner, "test_Operators::3");
        assertEq(operator, address(0), "test_Operators::4");

        vm.prank(owner);
        factory.setOperator(IStrategy(strategy), address(1));

        (defaultOperator, operator) = ISimpleVault(vault).getOperators();

        assertEq(defaultOperator, owner, "test_Operators::5");
        assertEq(operator, address(1), "test_Operators::6");
    }

    function test_GetStrategy() external {
        assertEq(address(ISimpleVault(vault).getStrategy()), address(0), "test_GetStrategy::1");

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        assertEq(address(ISimpleVault(vault).getStrategy()), strategy, "test_GetStrategy::2");
    }

    function test_GetStrategistFee() external {
        assertEq(ISimpleVault(vault).getStrategistFee(), 0, "test_GetStrategistFee::1");

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        assertEq(ISimpleVault(vault).getStrategistFee(), 0.1e4, "test_GetStrategistFee::2");
    }

    function test_GetBalances() external {
        (uint256 x, uint256 y) = ISimpleVault(vault).getBalances();

        assertEq(x, 0, "test_GetBalances::1");
        assertEq(y, 0, "test_GetBalances::2");

        deal(wavax, vault, 1e18);
        deal(usdc, vault, 1e18);

        (x, y) = ISimpleVault(vault).getBalances();

        assertEq(x, 1e18, "test_GetBalances::3");
        assertEq(y, 1e18, "test_GetBalances::4");

        deal(wavax, strategy, 1e18);
        deal(usdc, strategy, 1e18);

        (x, y) = ISimpleVault(vault).getBalances();

        assertEq(x, 1e18, "test_GetBalances::5");
        assertEq(y, 1e18, "test_GetBalances::6");

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        (x, y) = ISimpleVault(vault).getBalances();

        assertEq(x, 2e18, "test_GetBalances::7");
        assertEq(y, 2e18, "test_GetBalances::8");

        vm.prank(owner);
        factory.pauseVault(vault);

        (x, y) = ISimpleVault(vault).getBalances();

        assertEq(x, 2e18, "test_GetBalances::9");
        assertEq(y, 2e18, "test_GetBalances::10");
    }

    function test_GetRange() external {
        (uint24 low, uint24 upper) = ISimpleVault(vault).getRange();

        assertEq(low, 0, "test_GetRange::1");
        assertEq(upper, 0, "test_GetRange::2");

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        (low, upper) = ISimpleVault(vault).getRange();

        assertEq(low, 0, "test_GetRange::3");
        assertEq(upper, 0, "test_GetRange::4");
    }

    function test_GetPendingFees() external {
        (uint256 x, uint256 y) = ISimpleVault(vault).getPendingFees();

        assertEq(x, 0, "test_GetPendingFees::1");
        assertEq(y, 0, "test_GetPendingFees::2");

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        (x, y) = ISimpleVault(vault).getPendingFees();

        assertEq(x, 0, "test_GetPendingFees::3");
        assertEq(y, 0, "test_GetPendingFees::4");
    }

    function testFuzz_PreviewShares(uint128 x, uint128 y) external {
        (uint256 shares, uint256 effectiveX, uint256 effectiveY) = ISimpleVault(vault).previewShares(x, y);

        assertEq(effectiveX, x, "testFuzz_PreviewShares::1");
        assertEq(effectiveY, y, "testFuzz_PreviewShares::2");

        uint256 max = x > y ? x : y;

        assertEq(shares, max << 128, "testFuzz_PreviewShares::3");
    }

    function test_revert_PreviewShares(uint256 x, uint256 y) external {
        vm.assume(x > type(uint128).max || y > type(uint128).max);

        vm.expectRevert(ISimpleVault.SimpleVault__AmountsOverflow.selector);
        ISimpleVault(vault).previewShares(x, y);
    }

    function test_Deposit() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e18);

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, type(uint256).max);
        IERC20Upgradeable(usdc).approve(vault, type(uint256).max);

        ISimpleVault(vault).deposit(1e18, 1e18);
        vm.stopPrank();

        deal(wavax, bob, 0.5e18);
        deal(usdc, bob, 1e18);

        vm.startPrank(bob);
        IERC20Upgradeable(wavax).approve(vault, type(uint256).max);
        IERC20Upgradeable(usdc).approve(vault, type(uint256).max);

        ISimpleVault(vault).deposit(0.5e18, 1e18);
        vm.stopPrank();

        assertEq(IERC20Upgradeable(vault).balanceOf(alice), (1e18 << 128) - 1e6, "test_Deposit::1");
        assertEq(IERC20Upgradeable(vault).balanceOf(bob), 0.5e18 << 128, "test_Deposit::2");

        assertEq(IERC20Upgradeable(wavax).balanceOf(alice), 0, "test_Deposit::3");
        assertEq(IERC20Upgradeable(usdc).balanceOf(alice), 0, "test_Deposit::4");

        assertEq(IERC20Upgradeable(wavax).balanceOf(bob), 0, "test_Deposit::5");
        assertEq(IERC20Upgradeable(usdc).balanceOf(bob), 0.5e18, "test_Deposit::6");
    }

    function test_DepositOnlyX() external {
        deal(wavax, alice, 1e18);

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, type(uint256).max);

        ISimpleVault(vault).deposit(1e18, 0);
        vm.stopPrank();

        deal(wavax, bob, 0.5e18);
        deal(usdc, bob, 1e18);

        vm.startPrank(bob);
        IERC20Upgradeable(wavax).approve(vault, type(uint256).max);
        IERC20Upgradeable(usdc).approve(vault, type(uint256).max);

        ISimpleVault(vault).deposit(0.5e18, 1e18);
        vm.stopPrank();

        assertEq(IERC20Upgradeable(vault).balanceOf(alice), (1e18 << 128) - 1e6, "test_DepositOnlyX::1");
        assertEq(IERC20Upgradeable(vault).balanceOf(bob), 0.5e18 << 128, "test_DepositOnlyX::2");

        assertEq(IERC20Upgradeable(wavax).balanceOf(alice), 0, "test_DepositOnlyX::3");

        assertEq(IERC20Upgradeable(wavax).balanceOf(bob), 0, "test_DepositOnlyX::5");
        assertEq(IERC20Upgradeable(usdc).balanceOf(bob), 1e18, "test_DepositOnlyX::6");
    }

    function test_DepositOnlyY() external {
        deal(usdc, alice, 1e18);

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        vm.startPrank(alice);
        IERC20Upgradeable(usdc).approve(vault, type(uint256).max);

        ISimpleVault(vault).deposit(0, 1e18);
        vm.stopPrank();

        deal(wavax, bob, 0.5e18);
        deal(usdc, bob, 1e18);

        vm.startPrank(bob);
        IERC20Upgradeable(wavax).approve(vault, type(uint256).max);
        IERC20Upgradeable(usdc).approve(vault, type(uint256).max);

        ISimpleVault(vault).deposit(0.5e18, 1e18);
        vm.stopPrank();

        assertEq(IERC20Upgradeable(vault).balanceOf(alice), (1e18 << 128) - 1e6, "test_DepositOnlyY::1");
        assertEq(IERC20Upgradeable(vault).balanceOf(bob), 1e18 << 128, "test_DepositOnlyY::2");

        assertEq(IERC20Upgradeable(usdc).balanceOf(alice), 0, "test_DepositOnlyY::4");

        assertEq(IERC20Upgradeable(wavax).balanceOf(bob), 0.5e18, "test_DepositOnlyY::5");
        assertEq(IERC20Upgradeable(usdc).balanceOf(bob), 0, "test_DepositOnlyY::6");
    }

    function test_revert_DepositZeroCross() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e18);

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, type(uint256).max);
        IERC20Upgradeable(usdc).approve(vault, type(uint256).max);

        ISimpleVault(vault).deposit(1e18, 1e18);

        IERC20Upgradeable(wavax).approve(vault, type(uint256).max);
        IERC20Upgradeable(usdc).approve(vault, type(uint256).max);

        vm.expectRevert(ISimpleVault.SimpleVault__ZeroCross.selector);
        ISimpleVault(vault).deposit(0, 1e18);

        vm.expectRevert(ISimpleVault.SimpleVault__ZeroCross.selector);
        ISimpleVault(vault).deposit(1e18, 0);
        vm.stopPrank();
    }

    function test_revert_DepsitTotalAmountsOverflow() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e18);

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        vm.startPrank(alice);
        IERC20Upgradeable(wavax).approve(vault, type(uint256).max);
        IERC20Upgradeable(usdc).approve(vault, type(uint256).max);

        ISimpleVault(vault).deposit(1e18, 1e18);
        vm.stopPrank();

        deal(wavax, bob, (1 << 128) - 1e18);
        deal(usdc, bob, (1 << 128) - 1e18);

        vm.startPrank(bob);
        IERC20Upgradeable(wavax).transfer(vault, (1 << 128) - 1e18);
        IERC20Upgradeable(usdc).transfer(vault, (1 << 128) - 1e18);

        vm.expectRevert(ISimpleVault.SimpleVault__AmountsOverflow.selector);
        ISimpleVault(vault).deposit(1e18, 1e18);
        vm.stopPrank();
    }

    function test_DepositNativeAvaxIsX() external {
        deal(usdc, alice, 1e18);

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        vm.startPrank(alice);
        vm.deal(alice, 10e18);
        IERC20Upgradeable(usdc).approve(vault, type(uint256).max);

        ISimpleVault(vault).depositNative{value: 1e18}(1e18, 1e18);
        vm.stopPrank();

        deal(usdc, bob, 1e18);

        vm.startPrank(bob);
        vm.deal(bob, 10e18);
        IERC20Upgradeable(usdc).approve(vault, type(uint256).max);

        uint256 balance = bob.balance;
        ISimpleVault(vault).depositNative{value: 2e18}(2e18, 1e18);
        uint256 balanceAfter = bob.balance;
        vm.stopPrank();

        assertEq(balanceAfter, balance - 1e18, "test_DepositNative::1");
        assertEq(
            ISimpleVault(vault).balanceOf(alice) + 1e6, ISimpleVault(vault).balanceOf(bob), "test_DepositNative::2"
        );
    }

    function test_DepositNativeAvaxIsY() external {
        vm.prank(owner);
        (address nativeIsYVault,) = factory.createSimpleVaultAndDefaultStrategy(ILBPair(joe_wavax_15bp));

        vm.deal(alice, 10e18);
        deal(joe, alice, 1e18);

        vm.startPrank(alice);
        IERC20Upgradeable(joe).approve(nativeIsYVault, type(uint256).max);

        ISimpleVault(nativeIsYVault).depositNative{value: 1e18}(1e18, 1e18);
        vm.stopPrank();

        deal(joe, bob, 1e18);

        vm.startPrank(bob);
        vm.deal(bob, 10e18);
        IERC20Upgradeable(joe).approve(nativeIsYVault, type(uint256).max);

        uint256 balance = bob.balance;
        ISimpleVault(nativeIsYVault).depositNative{value: 2e18}(1e18, 2e18);
        uint256 balanceAfter = bob.balance;
        vm.stopPrank();

        assertEq(balanceAfter, balance - 1e18, "test_DepositNative::1");
        assertEq(
            ISimpleVault(nativeIsYVault).balanceOf(alice) + 1e6,
            ISimpleVault(nativeIsYVault).balanceOf(bob),
            "test_DepositNative::2"
        );
    }

    function test_revert_DepositNative() external {
        vm.prank(owner);
        (address noNativeVault,) = factory.createSimpleVaultAndDefaultStrategy(ILBPair(usdt_usdc_1bp));

        vm.expectRevert(IBaseVault.BaseVault__NoNativeToken.selector);
        ISimpleVault(noNativeVault).depositNative{value: 1e18}(1e18, 1e18);

        vm.prank(owner);
        (address nativeIsYVault,) = factory.createSimpleVaultAndDefaultStrategy(ILBPair(joe_wavax_15bp));

        vm.expectRevert(IBaseVault.BaseVault__InvalidNativeAmount.selector);
        ISimpleVault(nativeIsYVault).depositNative{value: 1e18}(1e18, 1e18 + 1);

        vm.expectRevert(IBaseVault.BaseVault__InvalidNativeAmount.selector);
        ISimpleVault(vault).depositNative{value: 1e18}(1e18 + 1, 1e18);

        vm.prank(owner);
        factory.linkVaultToStrategy(vault, strategy);

        deal(usdc, address(this), 2e18);
        IERC20Upgradeable(usdc).approve(vault, type(uint256).max);

        ISimpleVault(vault).depositNative{value: 1e18}(1e18, 1e18);

        vm.expectRevert(IBaseVault.BaseVault__NativeTransferFailed.selector);
        ISimpleVault(vault).depositNative{value: 2e18}(2e18, 1e18);
    }
}
