// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./TestHelper.sol";

contract SimpleVaultTest is TestHelper {
    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        vault = factory.createSimpleVault(ILBPair(wavax_usdc_20bp));
        strategy = factory.createDefaultStrategy(IBaseVault(vault));
        vm.stopPrank();

        vm.label(vault, "Vault Clone");
        vm.label(strategy, "Strategy Clone");

        vm.prank(address(factory));
        IStrategy(strategy).setPendingAumAnnualFee(0.1e4); // 10%
    }

    function test_revert_initializeTwice() external {
        vm.expectRevert("Initializable: contract is already initialized");
        ISimpleVault(vault).initialize("", "");
    }

    function test_GetImmutableData() external {
        assertEq(address(ISimpleVault(vault).getPair()), wavax_usdc_20bp, "test_GetImmutableData::1");
        assertEq(address(ISimpleVault(vault).getTokenX()), wavax, "test_GetImmutableData::2");
        assertEq(address(ISimpleVault(vault).getTokenY()), usdc, "test_GetImmutableData::3");
    }

    function test_Operators() external {
        (address defaultOperator, address operator) = ISimpleVault(vault).getOperators();

        assertEq(defaultOperator, owner, "test_Operators::1");
        assertEq(operator, address(0), "test_Operators::2");

        vm.prank(owner);
        factory.linkVaultToStrategy(IBaseVault(vault), strategy);

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
        factory.linkVaultToStrategy(IBaseVault(vault), strategy);

        assertEq(address(ISimpleVault(vault).getStrategy()), strategy, "test_GetStrategy::2");
    }

    function test_GetAumAnnualFee() external {
        assertEq(ISimpleVault(vault).getAumAnnualFee(), 0, "test_GetAumAnnualFee::1");

        vm.startPrank(owner);
        factory.linkVaultToStrategy(IBaseVault(vault), strategy);

        deal(wavax, strategy, 4e18);
        deal(usdc, strategy, 80e6);

        uint256[] memory desiredL = new uint256[](3);
        (desiredL[0], desiredL[1], desiredL[2]) = (20e6, 40e6, 20e6);

        IStrategy(strategy).rebalance((1 << 23) - 1, (1 << 23) + 1, 1 << 23, 1 << 23, desiredL, 1e18, 1e18);
        vm.stopPrank();

        assertEq(ISimpleVault(vault).getAumAnnualFee(), 0.1e4, "test_GetAumAnnualFee::2");
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
        factory.linkVaultToStrategy(IBaseVault(vault), strategy);

        (x, y) = ISimpleVault(vault).getBalances();

        assertEq(x, 2e18, "test_GetBalances::7");
        assertEq(y, 2e18, "test_GetBalances::8");

        vm.prank(owner);
        factory.setEmergencyMode(IBaseVault(vault));

        (x, y) = ISimpleVault(vault).getBalances();

        assertEq(x, 2e18, "test_GetBalances::9");
        assertEq(y, 2e18, "test_GetBalances::10");
    }

    function test_GetRange() external {
        (uint24 low, uint24 upper) = ISimpleVault(vault).getRange();

        assertEq(low, 0, "test_GetRange::1");
        assertEq(upper, 0, "test_GetRange::2");

        vm.prank(owner);
        factory.linkVaultToStrategy(IBaseVault(vault), strategy);

        (low, upper) = ISimpleVault(vault).getRange();

        assertEq(low, 0, "test_GetRange::3");
        assertEq(upper, 0, "test_GetRange::4");
    }

    function testFuzz_PreviewShares(uint128 x, uint128 y) external {
        (uint256 shares, uint256 effectiveX, uint256 effectiveY) = ISimpleVault(vault).previewShares(x, y);

        assertEq(effectiveX, x, "testFuzz_PreviewShares::1");
        assertEq(effectiveY, y, "testFuzz_PreviewShares::2");

        uint256 max = x > y ? x : y;

        assertEq(shares, max * 1e6, "testFuzz_PreviewShares::3");
    }

    function test_revert_PreviewShares(uint256 x, uint256 y) external {
        vm.assume(x > type(uint128).max || y > type(uint128).max);

        vm.expectRevert(ISimpleVault.SimpleVault__AmountsOverflow.selector);
        ISimpleVault(vault).previewShares(x, y);
    }

    function test_Deposit() external {
        linkVaultToStrategy(vault, strategy);
        depositToVault(vault, alice, 1e18, 1e18);
        depositToVault(vault, bob, 0.5e18, 1e18);

        assertEq(IERC20Upgradeable(vault).balanceOf(alice), (1e18 * 1e6) - 1e6, "test_Deposit::1");
        assertEq(IERC20Upgradeable(vault).balanceOf(bob), 0.5e18 * 1e6, "test_Deposit::2");

        assertEq(IERC20Upgradeable(wavax).balanceOf(alice), 0, "test_Deposit::3");
        assertEq(IERC20Upgradeable(usdc).balanceOf(alice), 0, "test_Deposit::4");

        assertEq(IERC20Upgradeable(wavax).balanceOf(bob), 0, "test_Deposit::5");
        assertEq(IERC20Upgradeable(usdc).balanceOf(bob), 0.5e18, "test_Deposit::6");
    }

    function test_DepositOnlyX() external {
        linkVaultToStrategy(vault, strategy);
        depositToVault(vault, alice, 1e18, 0);
        depositToVault(vault, bob, 0.5e18, 1e18);

        assertEq(IERC20Upgradeable(vault).balanceOf(alice), (1e18 * 1e6) - 1e6, "test_DepositOnlyX::1");
        assertEq(IERC20Upgradeable(vault).balanceOf(bob), 0.5e18 * 1e6, "test_DepositOnlyX::2");

        assertEq(IERC20Upgradeable(wavax).balanceOf(alice), 0, "test_DepositOnlyX::3");

        assertEq(IERC20Upgradeable(wavax).balanceOf(bob), 0, "test_DepositOnlyX::5");
        assertEq(IERC20Upgradeable(usdc).balanceOf(bob), 1e18, "test_DepositOnlyX::6");
    }

    function test_DepositOnlyY() external {
        linkVaultToStrategy(vault, strategy);
        depositToVault(vault, alice, 0, 1e18);
        depositToVault(vault, bob, 0.5e18, 1e18);

        assertEq(IERC20Upgradeable(vault).balanceOf(alice), (1e18 * 1e6) - 1e6, "test_DepositOnlyY::1");
        assertEq(IERC20Upgradeable(vault).balanceOf(bob), 1e18 * 1e6, "test_DepositOnlyY::2");

        assertEq(IERC20Upgradeable(usdc).balanceOf(alice), 0, "test_DepositOnlyY::4");

        assertEq(IERC20Upgradeable(wavax).balanceOf(bob), 0.5e18, "test_DepositOnlyY::5");
        assertEq(IERC20Upgradeable(usdc).balanceOf(bob), 0, "test_DepositOnlyY::6");
    }

    function test_revert_DepositZeroCross() external {
        deal(wavax, alice, 1e18);
        deal(usdc, alice, 1e18);

        linkVaultToStrategy(vault, strategy);

        depositToVault(vault, alice, 1e18, 1e18);

        vm.expectRevert(ISimpleVault.SimpleVault__ZeroCross.selector);
        this.depositToVault(vault, alice, 0, 1e18);

        vm.expectRevert(ISimpleVault.SimpleVault__ZeroCross.selector);
        this.depositToVault(vault, alice, 1e18, 0);
    }

    function test_revert_DepositTotalAmountsOverflow() external {
        linkVaultToStrategy(vault, strategy);
        depositToVault(vault, alice, 1e18, 1e18);
        depositToVault(vault, bob, (1 << 128) - 1e18, (1 << 128) - 1e18);

        vm.expectRevert(ISimpleVault.SimpleVault__AmountsOverflow.selector);
        ISimpleVault(vault).deposit(1, 1);
    }

    function test_revert_Deposit() external {
        vm.expectRevert(IBaseVault.BaseVault__ZeroAmount.selector);
        this.depositToVault(vault, alice, 0, 0);

        vm.expectRevert(IBaseVault.BaseVault__InvalidStrategy.selector);
        this.depositToVault(vault, alice, 1e18, 1e18);

        linkVaultToStrategy(vault, strategy);

        depositToVault(vault, alice, 0, 1e18);

        vm.expectRevert(IBaseVault.BaseVault__ZeroShares.selector);
        this.depositToVault(vault, alice, 1e18, 0);
    }

    function test_DepositNativeAvaxIsX() external {
        linkVaultToStrategy(vault, strategy);
        depositNativeToVault(vault, alice, 1e18, 1e18);

        uint256 balance = bob.balance + 2e18;
        depositNativeToVault(vault, bob, 2e18, 1e18);
        uint256 balanceAfter = bob.balance;

        assertEq(balanceAfter, balance - 1e18, "test_DepositNative::1");
        assertEq(
            ISimpleVault(vault).balanceOf(alice) + 1e6, ISimpleVault(vault).balanceOf(bob), "test_DepositNative::2"
        );
    }

    function test_DepositNativeAvaxIsY() external {
        vm.prank(owner);
        (address nativeIsYVault,) = factory.createSimpleVaultAndDefaultStrategy(ILBPair(joe_wavax_15bp));

        depositNativeToVault(nativeIsYVault, alice, 1e18, 1e18);

        uint256 balance = bob.balance + 2e18;
        depositNativeToVault(nativeIsYVault, bob, 1e18, 2e18);
        uint256 balanceAfter = bob.balance;
        vm.stopPrank();

        assertEq(balanceAfter, balance - 1e18, "test_DepositNative::1");
        assertEq(
            ISimpleVault(nativeIsYVault).balanceOf(alice) + 1e6,
            ISimpleVault(nativeIsYVault).balanceOf(bob),
            "test_DepositNative::2"
        );
    }

    function test_DepositZeroNativeX() external {
        linkVaultToStrategy(vault, strategy);
        depositNativeToVault(vault, alice, 0, 1e18);

        depositNativeToVault(vault, bob, 0.5e18, 1e18);

        assertEq(bob.balance, 0.5e18, "test_DepositZeroNativeX::1");
    }

    function test_DepositZeroTokenNativeIsX() external {
        linkVaultToStrategy(vault, strategy);
        depositNativeToVault(vault, alice, 1e18, 0);

        depositNativeToVault(vault, bob, 1e18, 0.5e18);

        assertEq(IERC20(usdc).balanceOf(bob), 0.5e18, "test_DepositZeroTokenNativeIsX::1");
    }

    function test_DepositZeroNativeY() external {
        vm.prank(owner);
        (address vault,) = factory.createSimpleVaultAndDefaultStrategy(ILBPair(joe_wavax_15bp));

        depositNativeToVault(vault, alice, 1e18, 0);

        depositNativeToVault(vault, bob, 1e18, 0.5e18);

        assertEq(bob.balance, 0.5e18, "test_DepositZeroNativeY::1");
    }

    function test_DepositZeroTokenNativeIsY() external {
        vm.prank(owner);
        (address vault,) = factory.createSimpleVaultAndDefaultStrategy(ILBPair(joe_wavax_15bp));

        depositNativeToVault(vault, alice, 0, 1e18);

        depositNativeToVault(vault, bob, 0.5e18, 1e18);

        assertEq(IERC20(joe).balanceOf(bob), 0.5e18, "test_DepositZeroTokenNativeIsY::1");
    }

    function test_revert_DepositNative() external {
        vm.prank(owner);
        (address noNativeVault,) = factory.createSimpleVaultAndDefaultStrategy(ILBPair(usdt_usdc_1bp));

        vm.expectRevert(IBaseVault.BaseVault__NoNativeToken.selector);
        this.depositNativeToVault(noNativeVault, alice, 1e18, 1e18);

        vm.prank(owner);
        (address nativeIsYVault,) = factory.createSimpleVaultAndDefaultStrategy(ILBPair(joe_wavax_15bp));

        vm.expectRevert(IBaseVault.BaseVault__InvalidNativeAmount.selector);
        ISimpleVault(nativeIsYVault).depositNative{value: 1e18}(1e18, 1e18 + 1);

        vm.expectRevert(IBaseVault.BaseVault__InvalidNativeAmount.selector);
        ISimpleVault(vault).depositNative{value: 1e18}(1e18 + 1, 1e18);

        vm.prank(owner);
        factory.linkVaultToStrategy(IBaseVault(vault), strategy);

        deal(usdc, address(this), 2e18);
        IERC20Upgradeable(usdc).approve(vault, type(uint256).max);

        depositToVault(vault, alice, 1e18, 1e18);

        vm.expectRevert(IBaseVault.BaseVault__NativeTransferFailed.selector);
        this.depositNativeToVault(vault, address(this), 2e18, 1e18);
    }

    function test_SetStrategy() external {
        linkVaultToStrategy(vault, strategy);

        vm.startPrank(owner);
        address newStrategy = factory.createDefaultStrategy(IBaseVault(vault));

        factory.linkVaultToStrategy(IBaseVault(vault), newStrategy);
        vm.stopPrank();
    }

    function test_revert_SetStrategy() external {
        address newStrategy = address(new MockStrategy());

        vm.startPrank(address(factory));
        vm.expectRevert(IBaseVault.BaseVault__InvalidStrategy.selector);
        IBaseVault(vault).setStrategy(IStrategy(newStrategy));

        MockStrategy(newStrategy).set(vault, address(0), address(0), address(0));

        vm.expectRevert(IBaseVault.BaseVault__InvalidStrategy.selector);
        IBaseVault(vault).setStrategy(IStrategy(newStrategy));

        MockStrategy(newStrategy).set(vault, wavax_usdc_20bp, address(0), address(0));

        vm.expectRevert(IBaseVault.BaseVault__InvalidStrategy.selector);
        IBaseVault(vault).setStrategy(IStrategy(newStrategy));

        MockStrategy(newStrategy).set(vault, wavax_usdc_20bp, wavax, address(0));

        vm.expectRevert(IBaseVault.BaseVault__InvalidStrategy.selector);
        IBaseVault(vault).setStrategy(IStrategy(newStrategy));

        MockStrategy(newStrategy).set(vault, wavax_usdc_20bp, wavax, usdc);

        IBaseVault(vault).setStrategy(IStrategy(newStrategy));

        vm.expectRevert(IBaseVault.BaseVault__SameStrategy.selector);
        IBaseVault(vault).setStrategy(IStrategy(newStrategy));

        vm.stopPrank();
    }

    function test_RecoverVaultToken() external {
        linkVaultToStrategy(vault, strategy);
        depositToVault(vault, alice, 1e18, 1e18);

        uint256 balance = IERC20Upgradeable(vault).balanceOf(alice);

        vm.prank(alice);
        IERC20(vault).transfer(address(vault), balance);

        assertEq(IERC20Upgradeable(vault).balanceOf(vault), balance + 1e6, "test_RecoverERC20::1");

        vm.expectRevert(IBaseVault.BaseVault__BurnMinShares.selector);
        vm.prank(address(factory));
        IBaseVault(vault).recoverERC20(IERC20Upgradeable(vault), alice, balance + 1);

        vm.prank(address(factory));
        IBaseVault(vault).recoverERC20(IERC20Upgradeable(vault), alice, balance);

        assertEq(IERC20Upgradeable(vault).balanceOf(vault), 1e6, "test_RecoverERC20::2");
        assertEq(IERC20Upgradeable(vault).balanceOf(alice), balance, "test_RecoverERC20::3");

        vm.prank(alice);
        IERC20(vault).transfer(strategy, balance);

        vm.expectRevert(IBaseVault.BaseVault__BurnMinShares.selector);
        vm.prank(address(factory));
        IBaseVault(vault).recoverERC20(IERC20Upgradeable(vault), alice, balance + 1);

        vm.prank(address(factory));
        IBaseVault(vault).recoverERC20(IERC20Upgradeable(vault), alice, balance);

        assertEq(IERC20Upgradeable(vault).balanceOf(vault), 1e6, "test_RecoverERC20::4");
        assertEq(IERC20Upgradeable(vault).balanceOf(strategy), 0, "test_RecoverERC20::5");

        assertEq(IERC20Upgradeable(vault).balanceOf(alice), balance, "test_RecoverERC20::6");
    }

    function test_ReceiveNativeFromWNative() external {
        vm.prank(wavax);
        (bool s,) = vault.call{value: 1e18}("");
        require(s);
    }

    function test_revert_SendEthToVaul() external {
        vm.expectRevert();
        payable(vault).transfer(1e18);

        vm.expectRevert(IBaseVault.BaseVault__OnlyWNative.selector);
        (bool s,) = vault.call{value: 1e18}("");
        require(s);
    }

    function test_Decimals() external {
        assertEq(IERC20MetadataUpgradeable(vault).decimals(), 6 + 6, "test_Decimals::1");
    }

    function test_QueueAndRedeem() external {
        linkVaultToStrategy(vault, strategy);
        depositToVault(vault, alice, 1e18, 1e18);

        uint256 shares = IERC20Upgradeable(vault).balanceOf(alice);

        (uint256 amountX, uint256 amountY) = IBaseVault(vault).previewAmounts(shares);

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(shares, alice);

        assertEq(IERC20Upgradeable(vault).balanceOf(alice), 0, "test_QueueWithdrawal::1");

        uint256 round = IBaseVault(vault).getCurrentRound();

        assertEq(round, 0, "test_QueueWithdrawal::2");

        uint256 qShares = IBaseVault(vault).getQueuedWithdrawal(0, alice);
        uint256 tShares = IBaseVault(vault).getTotalQueuedWithdrawal(0);

        assertEq(tShares, shares, "test_QueueWithdrawal::3");
        assertEq(qShares, shares, "test_QueueWithdrawal::4");

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        (uint256 balanceX, uint256 balanceY) = IBaseVault(vault).getBalances();
        (uint256 rAmountX, uint256 rAmountY) = IBaseVault(vault).getRedeemableAmounts(0, alice);

        vm.prank(alice);
        IBaseVault(vault).redeemQueuedWithdrawal(0, alice);

        assertEq(IERC20(wavax).balanceOf(alice), amountX, "test_QueueWithdrawal::5");
        assertEq(IERC20(usdc).balanceOf(alice), amountY, "test_QueueWithdrawal::6");

        assertEq(rAmountX, amountX, "test_QueueWithdrawal::7");
        assertEq(rAmountY, amountY, "test_QueueWithdrawal::8");

        assertEq(IBaseVault(vault).getQueuedWithdrawal(0, alice), 0, "test_QueueWithdrawal::9");

        (uint256 balanceX2, uint256 balanceY2) = IBaseVault(vault).getBalances();

        assertEq(balanceX2, balanceX, "test_QueueWithdrawal::10");
        assertEq(balanceY2, balanceY, "test_QueueWithdrawal::11");
    }

    function test_QueueAndRedeemNative() external {
        linkVaultToStrategy(vault, strategy);
        depositToVault(vault, alice, 1e18, 1e18);

        uint256 shares = IERC20Upgradeable(vault).balanceOf(alice);

        (uint256 amountX, uint256 amountY) = IBaseVault(vault).previewAmounts(shares);

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(shares, alice);

        assertEq(IERC20Upgradeable(vault).balanceOf(alice), 0, "test_QueueWithdrawal::1");

        uint256 round = IBaseVault(vault).getCurrentRound();

        assertEq(round, 0, "test_QueueWithdrawal::2");

        uint256 qShares = IBaseVault(vault).getQueuedWithdrawal(0, alice);
        uint256 tShares = IBaseVault(vault).getTotalQueuedWithdrawal(0);

        assertEq(tShares, shares, "test_QueueWithdrawal::3");
        assertEq(qShares, shares, "test_QueueWithdrawal::4");

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        (uint256 balanceX, uint256 balanceY) = IBaseVault(vault).getBalances();
        (uint256 rAmountX, uint256 rAmountY) = IBaseVault(vault).getRedeemableAmounts(0, alice);

        vm.prank(alice);
        IBaseVault(vault).redeemQueuedWithdrawalNative(0, alice);

        assertEq(alice.balance, amountX, "test_QueueWithdrawal::5");
        assertEq(IERC20(usdc).balanceOf(alice), amountY, "test_QueueWithdrawal::6");

        assertEq(rAmountX, amountX, "test_QueueWithdrawal::7");
        assertEq(rAmountY, amountY, "test_QueueWithdrawal::8");

        assertEq(IBaseVault(vault).getQueuedWithdrawal(0, alice), 0, "test_QueueWithdrawal::9");

        (uint256 balanceX2, uint256 balanceY2) = IBaseVault(vault).getBalances();

        assertEq(balanceX2, balanceX, "test_QueueWithdrawal::10");
        assertEq(balanceY2, balanceY, "test_QueueWithdrawal::11");
    }

    function test_QueueAndCancel() external {
        linkVaultToStrategy(vault, strategy);
        depositToVault(vault, alice, 1e18, 1e18);

        uint256 shares = IERC20Upgradeable(vault).balanceOf(alice);

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(shares, alice);

        assertEq(IERC20Upgradeable(vault).balanceOf(alice), 0, "test_QueueWithdrawal::1");
        assertEq(IERC20Upgradeable(vault).balanceOf(strategy), shares, "test_QueueWithdrawal::2");

        vm.prank(alice);
        IBaseVault(vault).cancelQueuedWithdrawal(shares / 2);

        assertEq(IERC20Upgradeable(vault).balanceOf(alice), shares / 2, "test_QueueWithdrawal::3");
        assertEq(IBaseVault(vault).getQueuedWithdrawal(0, alice), shares - shares / 2, "test_QueueWithdrawal::4");
        assertEq(IBaseVault(vault).getTotalQueuedWithdrawal(0), shares - shares / 2, "test_QueueWithdrawal::5");
        assertEq(IERC20Upgradeable(vault).balanceOf(strategy), shares - shares / 2, "test_QueueWithdrawal::6");
    }

    function test_revert_QueueWithdrawal() external {
        vm.expectRevert(IBaseVault.BaseVault__InvalidStrategy.selector);
        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(1e18, alice);

        linkVaultToStrategy(vault, strategy);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(1, alice);

        vm.expectRevert(IBaseVault.BaseVault__ZeroShares.selector);
        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(0, alice);

        vm.expectRevert(IBaseVault.BaseVault__InvalidRecipient.selector);
        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(1e18, address(0));

        depositToVault(vault, alice, 1e18, 1e18);

        uint256 shares = IERC20Upgradeable(vault).balanceOf(alice);

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(shares, alice);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(1, alice);
    }

    function test_revert_CancelWithdrawal() external {
        vm.expectRevert(IBaseVault.BaseVault__ZeroShares.selector);
        vm.prank(alice);
        IBaseVault(vault).cancelQueuedWithdrawal(0);

        vm.expectRevert(IBaseVault.BaseVault__InvalidStrategy.selector);
        vm.prank(alice);
        IBaseVault(vault).cancelQueuedWithdrawal(1);

        linkVaultToStrategy(vault, strategy);

        vm.expectRevert(IBaseVault.BaseVault__MaxSharesExceeded.selector);
        vm.prank(alice);
        IBaseVault(vault).cancelQueuedWithdrawal(1);

        depositToVault(vault, alice, 1e18, 1e18);

        uint256 shares = IERC20Upgradeable(vault).balanceOf(alice);

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(shares, alice);

        vm.prank(alice);
        IBaseVault(vault).cancelQueuedWithdrawal(shares);

        vm.expectRevert(IBaseVault.BaseVault__MaxSharesExceeded.selector);
        vm.prank(alice);
        IBaseVault(vault).cancelQueuedWithdrawal(1);
    }

    function test_revert_RedeemQueuedWithdrawal() external {
        linkVaultToStrategy(vault, strategy);
        depositToVault(vault, alice, 1e18, 1e18);

        uint256 shares = IERC20Upgradeable(vault).balanceOf(alice);

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(shares, alice);

        vm.expectRevert(IBaseVault.BaseVault__InvalidRound.selector);
        vm.prank(alice);
        IBaseVault(vault).redeemQueuedWithdrawal(1, alice);

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        vm.expectRevert(IBaseVault.BaseVault__NoQueuedWithdrawal.selector);
        vm.prank(bob);
        IBaseVault(vault).redeemQueuedWithdrawal(0, bob);

        vm.expectRevert(IBaseVault.BaseVault__InvalidRecipient.selector);
        vm.prank(alice);
        IBaseVault(vault).redeemQueuedWithdrawal(0, address(0));

        vm.expectRevert(IBaseVault.BaseVault__Unauthorized.selector);
        IBaseVault(vault).redeemQueuedWithdrawal(0, alice);

        vm.prank(alice);
        IBaseVault(vault).redeemQueuedWithdrawal(0, alice);

        vm.expectRevert(IBaseVault.BaseVault__NoQueuedWithdrawal.selector);
        vm.prank(alice);
        IBaseVault(vault).redeemQueuedWithdrawal(0, alice);
    }

    function test_PreviewAmounts() external {
        linkVaultToStrategy(vault, strategy);
        depositToVault(vault, alice, 1e18, 1e18);

        uint256 shares = IERC20Upgradeable(vault).totalSupply();

        (uint256 amountX, uint256 amountY) = IBaseVault(vault).previewAmounts(0);

        assertEq(amountX, 0, "test_QueueWithdrawal::1");
        assertEq(amountY, 0, "test_QueueWithdrawal::2");

        (amountX, amountY) = IBaseVault(vault).previewAmounts(shares);

        assertEq(amountX, 1e18, "test_QueueWithdrawal::3");
        assertEq(amountY, 1e18, "test_QueueWithdrawal::4");

        vm.expectRevert(IBaseVault.BaseVault__InvalidShares.selector);
        (amountX, amountY) = IBaseVault(vault).previewAmounts(shares + 1);
    }

    function test_revert_ExecuteQueuedWithdrawals() external {
        vm.expectRevert(IBaseVault.BaseVault__OnlyStrategy.selector);
        IBaseVault(vault).executeQueuedWithdrawals();

        uint256 round = IBaseVault(vault).getCurrentRound();

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        vm.warp(block.timestamp + 3600);

        assertEq(IBaseVault(vault).getTotalQueuedWithdrawal(round), 0, "test_QueueWithdrawal::1");
        assertEq(IBaseVault(vault).getCurrentRound(), round, "test_QueueWithdrawal::2");

        linkVaultToStrategy(vault, strategy);
        depositToVault(vault, alice, 1e18, 1e18);

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(1, alice);

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        vm.prank(strategy);
        IBaseVault(vault).executeQueuedWithdrawals();

        assertEq(IBaseVault(vault).getTotalQueuedWithdrawal(round), 1, "test_QueueWithdrawal::3");
        assertEq(IBaseVault(vault).getCurrentRound(), round + 1, "test_QueueWithdrawal::4");
    }

    function test_EmergencyWithdraw() external {
        linkVaultToStrategy(vault, strategy);
        depositToVault(vault, alice, 1e18, 1e18);

        uint256 shares = IERC20Upgradeable(vault).balanceOf(alice);

        vm.prank(alice);
        IBaseVault(vault).queueWithdrawal(shares / 2, alice);

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        vm.expectRevert(IBaseVault.BaseVault__NotInEmergencyMode.selector);
        IBaseVault(vault).emergencyWithdraw();

        vm.prank(owner);
        factory.setEmergencyMode(IBaseVault(vault));

        vm.prank(alice);
        IBaseVault(vault).emergencyWithdraw();

        vm.expectRevert(IBaseVault.BaseVault__ZeroShares.selector);
        vm.prank(alice);
        IBaseVault(vault).emergencyWithdraw();

        assertEq(IERC20Upgradeable(wavax).balanceOf(alice), 0.5e18 - 1, "test_EmergencyWithdraw::1");
        assertEq(IERC20Upgradeable(wavax).balanceOf(vault), 0.5e18 + 1, "test_EmergencyWithdraw::2");

        assertEq(IERC20Upgradeable(usdc).balanceOf(alice), 0.5e18 - 1, "test_EmergencyWithdraw::3");
        assertEq(IERC20Upgradeable(usdc).balanceOf(vault), 0.5e18 + 1, "test_EmergencyWithdraw::4");

        vm.prank(alice);
        IBaseVault(vault).redeemQueuedWithdrawal(0, alice);

        assertEq(IERC20Upgradeable(wavax).balanceOf(alice), 1e18 - 2, "test_EmergencyWithdraw::5");
        assertEq(IERC20Upgradeable(wavax).balanceOf(vault), 2, "test_EmergencyWithdraw::6");

        assertEq(IERC20Upgradeable(usdc).balanceOf(alice), 1e18 - 2, "test_EmergencyWithdraw::7");
        assertEq(IERC20Upgradeable(usdc).balanceOf(vault), 2, "test_EmergencyWithdraw::8");
    }

    function test_revert_DepositNotWhitelisted() external {
        linkVaultToStrategy(vault, strategy);

        assertFalse(IBaseVault(vault).isWhitelistedOnly(), "test_revert_DepositNotWhitelisted::1");

        vm.startPrank(owner);
        vm.expectRevert(IBaseVault.BaseVault__SameWhitelistState.selector);
        factory.setWhitelistState(IBaseVault(vault), false);

        factory.setWhitelistState(IBaseVault(vault), true);

        vm.expectRevert(IBaseVault.BaseVault__SameWhitelistState.selector);
        factory.setWhitelistState(IBaseVault(vault), true);
        vm.stopPrank();

        assertTrue(IBaseVault(vault).isWhitelistedOnly(), "test_revert_DepositNotWhitelisted::2");

        vm.expectRevert(abi.encodeWithSelector(IBaseVault.BaseVault__NotWhitelisted.selector, alice));
        this.depositToVault(vault, alice, 1e18, 1e18);

        vm.prank(owner);
        factory.setWhitelistState(IBaseVault(vault), false);

        assertFalse(IBaseVault(vault).isWhitelistedOnly(), "test_revert_DepositNotWhitelisted::3");

        this.depositToVault(vault, alice, 1e18, 1e18);

        vm.startPrank(owner);
        factory.setWhitelistState(IBaseVault(vault), true);

        assertTrue(IBaseVault(vault).isWhitelistedOnly(), "test_revert_DepositNotWhitelisted::4");
        assertFalse(IBaseVault(vault).isWhitelisted(alice), "test_revert_DepositNotWhitelisted::5");

        address[] memory users = new address[](1);
        users[0] = alice;

        factory.addToWhitelist(IBaseVault(vault), users);

        vm.expectRevert(abi.encodeWithSelector(IBaseVault.BaseVault__AlreadyWhitelisted.selector, alice));
        factory.addToWhitelist(IBaseVault(vault), users);
        vm.stopPrank();

        assertTrue(IBaseVault(vault).isWhitelisted(alice), "test_revert_DepositNotWhitelisted::6");

        this.depositToVault(vault, alice, 1e18, 1e18);

        vm.expectRevert(abi.encodeWithSelector(IBaseVault.BaseVault__NotWhitelisted.selector, bob));
        this.depositToVault(vault, bob, 1e18, 1e18);

        vm.prank(owner);
        factory.removeFromWhitelist(IBaseVault(vault), users);

        vm.expectRevert(abi.encodeWithSelector(IBaseVault.BaseVault__NotWhitelisted.selector, alice));
        this.depositToVault(vault, alice, 1e18, 1e18);
    }
}

contract MockStrategy {
    address public getVault;
    address public getPair;
    address public getTokenX;
    address public getTokenY;

    function set(address _vault, address _pair, address _tokenX, address _tokenY) external {
        getVault = _vault;
        getPair = _pair;
        getTokenX = _tokenX;
        getTokenY = _tokenY;
    }
}
