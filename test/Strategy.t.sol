// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./TestHelper.sol";

contract StrategyTest is TestHelper {
    IAggregatorV3 dfX;
    IAggregatorV3 dfY;

    function setUp() public override {
        super.setUp();

        dfX = new MockAggregator();
        dfY = new MockAggregator();

        vm.prank(owner);
        (vault, strategy) = factory.createOracleVaultAndDefaultStrategy(ILBPair(wavax_usdc_20bp), dfX, dfY);
    }

    function test_GetImmutableData() external {
        assertEq(address(IStrategy(strategy).getVault()), vault, "test_GetImmutableData::1");
        assertEq(address(IStrategy(strategy).getPair()), wavax_usdc_20bp, "test_GetImmutableData::2");
        assertEq(address(IStrategy(strategy).getTokenX()), wavax, "test_GetImmutableData::3");
        assertEq(address(IStrategy(strategy).getTokenY()), usdc, "test_GetImmutableData::4");
    }

    function test_GetRange() external {
        (uint24 low, uint24 upper) = IStrategy(strategy).getRange();

        assertEq(low, 0, "test_GetRange::1");
        assertEq(upper, 0, "test_GetRange::2");
    }

    function test_GetOperator() external {
        assertEq(address(IStrategy(strategy).getOperator()), address(0), "test_GetOperator::1");

        vm.prank(owner);
        factory.setOperator(IStrategy(strategy), address(1));

        assertEq(address(IStrategy(strategy).getOperator()), address(1), "test_GetOperator::2");

        vm.prank(owner);
        factory.setOperator(IStrategy(strategy), address(0));

        assertEq(address(IStrategy(strategy).getOperator()), address(0), "test_GetOperator::3");
    }

    function test_revert_SetOperator() external {
        vm.expectRevert(IStrategy.Strategy__OnlyFactory.selector);
        IStrategy(strategy).setOperator(address(1));
    }

    function test_GetBalances() external {
        (uint256 x, uint256 y) = IStrategy(strategy).getBalances();

        assertEq(x, 0, "test_GetBalances::1");
        assertEq(y, 0, "test_GetBalances::2");

        deal(wavax, strategy, 1e18);
        deal(usdc, strategy, 1e6);

        (x, y) = IStrategy(strategy).getBalances();

        assertEq(x, 1e18, "test_GetBalances::3");
        assertEq(y, 1e6, "test_GetBalances::4");

        deal(wavax, vault, 1e18);
        deal(usdc, vault, 1e6);

        (x, y) = IStrategy(strategy).getBalances();

        assertEq(x, 1e18, "test_GetBalances::5");
        assertEq(y, 1e6, "test_GetBalances::6");
    }

    function test_GetPendingFees() external {
        (uint256 x, uint256 y) = IStrategy(strategy).getPendingFees();

        assertEq(x, 0, "test_GetPendingFees::1");
        assertEq(y, 0, "test_GetPendingFees::2");
    }

    function test_GetPendingAumFee() external {
        assertEq(IStrategy(strategy).getAumAnnualFee(), 0, "test_GetPendingAumFee::1");

        vm.prank(owner);
        factory.setPendingAumAnnualFee(IBaseVault(vault), 0.25e4);

        (bool isPending, uint256 pendingFee) = IStrategy(strategy).getPendingAumAnnualFee();

        assertTrue(isPending, "test_GetPendingAumFee::2");
        assertEq(pendingFee, 0.25e4, "test_GetPendingAumFee::3");

        vm.prank(owner);
        factory.setPendingAumAnnualFee(IBaseVault(vault), 0);

        (isPending, pendingFee) = IStrategy(strategy).getPendingAumAnnualFee();

        assertTrue(isPending, "test_GetPendingAumFee::4");
        assertEq(pendingFee, 0, "test_GetPendingAumFee::5");

        vm.prank(owner);
        factory.resetPendingAumAnnualFee(IBaseVault(vault));

        (isPending, pendingFee) = IStrategy(strategy).getPendingAumAnnualFee();

        assertFalse(isPending, "test_GetPendingAumFee::6");
        assertEq(pendingFee, 0, "test_GetPendingAumFee::7");
    }

    function test_revert_SetPendingAumAnnualFee() external {
        vm.expectRevert(IStrategy.Strategy__OnlyFactory.selector);
        IStrategy(strategy).setPendingAumAnnualFee(0.1e4);

        vm.expectRevert(IStrategy.Strategy__InvalidFee.selector);
        vm.prank(address(factory));
        IStrategy(strategy).setPendingAumAnnualFee(0.25e4 + 1);
    }

    function test_CollectFees() external {
        IStrategy(strategy).collectFees();

        assertEq(IERC20Upgradeable(wavax).balanceOf(address(strategy)), 0, "test_CollectFees::1");
        assertEq(IERC20Upgradeable(usdc).balanceOf(address(strategy)), 0, "test_CollectFees::2");
    }

    function test_RebalanceClose() public {
        uint256 amountX = 1e24;
        uint256 amountY = 1e18;

        deal(wavax, strategy, amountX);
        deal(usdc, strategy, amountY);

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory desiredL = new uint256[](3);
        (desiredL[0], desiredL[1], desiredL[2]) = (20e6, 40e6, 20e6);

        vm.prank(owner);
        IStrategy(strategy).rebalance(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, desiredL, 1e18, 1e18
        );

        (uint256 x, uint256 y) = IStrategy(strategy).getBalances();
        uint256 price = router.getPriceFromId(ILBPair(wavax_usdc_20bp), uint24(activeId));

        uint256 balancesInY = ((price * x) >> 128) + y;
        uint256 amountInY = ((price * amountX) >> 128) + amountY;

        assertApproxEqRel(balancesInY, amountInY, 1e14, "test_Rebalance::1");

        for (uint256 i = activeId - 1; i <= activeId + 1; i++) {
            uint256 balance = ILBToken(wavax_usdc_20bp).balanceOf(strategy, uint24(i));

            assertGt(balance, 0, "test_Rebalance::2");
        }
    }

    function test_revert_Rebalance() external {
        vm.expectRevert(IStrategy.Strategy__OnlyOperators.selector);
        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        vm.startPrank(address(owner));
        vm.expectRevert(IStrategy.Strategy__ZeroAmounts.selector);
        IStrategy(strategy).rebalance(0, 1, uint24(activeId), 0, new uint256[](2), 0, 0);

        vm.expectRevert(IStrategy.Strategy__InvalidRange.selector);
        IStrategy(strategy).rebalance(1, 0, uint24(activeId), 0, new uint256[](0), 0, 0);

        vm.expectRevert(IStrategy.Strategy__InvalidAmountsLength.selector);
        IStrategy(strategy).rebalance(1, 1, uint24(activeId), 0, new uint256[](0), 0, 0);

        vm.expectRevert(IStrategy.Strategy__ActiveIdSlippage.selector);
        IStrategy(strategy).rebalance(1, 1, uint24(activeId) + 1, 0, new uint256[](3), 0, 0);
        vm.stopPrank();
    }

    function test_WithdrawAll() external {
        uint256 amountX = 1e24;
        uint256 amountY = 1e18;

        deal(wavax, strategy, amountX);
        deal(usdc, strategy, amountY);

        uint256[] memory desiredL = new uint256[](3);
        (desiredL[0], desiredL[1], desiredL[2]) = (20e6, 40e6, 20e6);

        vm.startPrank(owner);
        IStrategy(strategy).rebalance((1 << 23) - 1, (1 << 23) + 1, 1 << 23, 1 << 23, desiredL, 1e18, 1e18);

        (uint256 x, uint256 y) = IStrategy(strategy).getBalances();

        IStrategy(strategy).rebalance(0, 0, 0, 0, new uint256[](0), 0, 0);
        vm.stopPrank();

        (uint256 x2, uint256 y2) = IStrategy(strategy).getBalances();

        assertEq(x2, x, "test_WithdrawAll::1");
        assertEq(y2, y, "test_WithdrawAll::2");

        uint256 bx = IERC20Upgradeable(wavax).balanceOf(address(strategy));
        uint256 by = IERC20Upgradeable(usdc).balanceOf(address(strategy));

        assertEq(bx, x, "test_WithdrawAll::3");
        assertEq(by, y, "test_WithdrawAll::4");
    }

    function test_Swap() external {
        string memory b =
            "12aa3caf000000000000000000000000f01ef4051130cc8871fa0c17024a6d62e379e856000000000000000000000000b31f66aa3c1e785363f0875a1b74e27b85fd66c7000000000000000000000000b97ef9ef8734c71904d8002f8b6bc66dd9c48a6e000000000000000000000000f4003f4efbe8691b60249e6afbd307abe7758adb0000000000000000000000008d2c17fad02b7bb64139109c6533b7c2b9cadb81000000000000000000000000000000000000000000000000002386f26fc100000000000000000000000000000000000000000000000000000000000000015afc0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008500000000000000000000000000000000000000000000000000000000006700206ae40711b8002dc6c0f4003f4efbe8691b60249e6afbd307abe7758adb1111111254eeb25477b68fb85ed929f73a9605820000000000000000000000000000000000000000000000000000000000015afcb31f66aa3c1e785363f0875a1b74e27b85fd66c7000000000000000000000000000000000000000000000000000000cfee7c08";

        deal(wavax, strategy, 0.01e18);

        vm.prank(owner);
        IStrategy(strategy).swap(_convertHexStringToBytes(b));

        b =
            "12aa3caf000000000000000000000000f01ef4051130cc8871fa0c17024a6d62e379e856000000000000000000000000b97ef9ef8734c71904d8002f8b6bc66dd9c48a6e000000000000000000000000b31f66aa3c1e785363f0875a1b74e27b85fd66c7000000000000000000000000f4003f4efbe8691b60249e6afbd307abe7758adb0000000000000000000000008d2c17fad02b7bb64139109c6533b7c2b9cadb8100000000000000000000000000000000000000000000000000000000000f424000000000000000000000000000000000000000000000000000636499f596bdc00000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008500000000000000000000000000000000000000000000000000000000006700206ae4071138002dc6c0f4003f4efbe8691b60249e6afbd307abe7758adb1111111254eeb25477b68fb85ed929f73a96058200000000000000000000000000000000000000000000000000636499f596bdc0b97ef9ef8734c71904d8002f8b6bc66dd9c48a6e000000000000000000000000000000000000000000000000000000cfee7c08";

        deal(usdc, strategy, 1e6);

        vm.prank(owner);
        IStrategy(strategy).swap(_convertHexStringToBytes(b));
    }

    function test_revert_Swap() external {
        vm.expectRevert(IStrategy.Strategy__OnlyOperators.selector);
        IStrategy(strategy).swap(new bytes(0));

        vm.startPrank(owner);
        vm.expectRevert(IStrategy.Strategy__InvalidData.selector);
        IStrategy(strategy).swap(new bytes(0xc3));

        string memory b =
            "12aa3caf000000000000000000000000f01ef4051130cc8871fa0c17024a6d62e379e8560000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b97ef9ef8734c71904d8002f8b6bc66dd9c48a6e000000000000000000000000f4003f4efbe8691b60249e6afbd307abe7758adb0000000000000000000000008d2c17fad02b7bb64139109c6533b7c2b9cadb81000000000000000000000000000000000000000000000000002386f26fc100000000000000000000000000000000000000000000000000000000000000015afc0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008500000000000000000000000000000000000000000000000000000000006700206ae40711b8002dc6c0f4003f4efbe8691b60249e6afbd307abe7758adb1111111254eeb25477b68fb85ed929f73a9605820000000000000000000000000000000000000000000000000000000000015afcb31f66aa3c1e785363f0875a1b74e27b85fd66c7000000000000000000000000000000000000000000000000000000cfee7c08";

        vm.expectRevert();
        IStrategy(strategy).swap(_convertHexStringToBytes(b));

        b =
            "12aa3caf000000000000000000000000f01ef4051130cc8871fa0c17024a6d62e379e856000000000000000000000000b31f66aa3c1e785363f0875a1b74e27b85fd66c70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f4003f4efbe8691b60249e6afbd307abe7758adb0000000000000000000000008d2c17fad02b7bb64139109c6533b7c2b9cadb81000000000000000000000000000000000000000000000000002386f26fc100000000000000000000000000000000000000000000000000000000000000015afc0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008500000000000000000000000000000000000000000000000000000000006700206ae40711b8002dc6c0f4003f4efbe8691b60249e6afbd307abe7758adb1111111254eeb25477b68fb85ed929f73a9605820000000000000000000000000000000000000000000000000000000000015afcb31f66aa3c1e785363f0875a1b74e27b85fd66c7000000000000000000000000000000000000000000000000000000cfee7c08";

        vm.expectRevert(IStrategy.Strategy__InvalidDstToken.selector);
        IStrategy(strategy).swap(_convertHexStringToBytes(b));

        b =
            "12aa3caf000000000000000000000000f01ef4051130cc8871fa0c17024a6d62e379e856000000000000000000000000b31f66aa3c1e785363f0875a1b74e27b85fd66c7000000000000000000000000b97ef9ef8734c71904d8002f8b6bc66dd9c48a6e000000000000000000000000f4003f4efbe8691b60249e6afbd307abe7758adb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002386f26fc100000000000000000000000000000000000000000000000000000000000000015afc0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008500000000000000000000000000000000000000000000000000000000006700206ae40711b8002dc6c0f4003f4efbe8691b60249e6afbd307abe7758adb1111111254eeb25477b68fb85ed929f73a9605820000000000000000000000000000000000000000000000000000000000015afcb31f66aa3c1e785363f0875a1b74e27b85fd66c7000000000000000000000000000000000000000000000000000000cfee7c08";

        vm.expectRevert(IStrategy.Strategy__InvalidReceiver.selector);
        IStrategy(strategy).swap(_convertHexStringToBytes(b));

        b =
            "12aa3caf000000000000000000000000f01ef4051130cc8871fa0c17024a6d62e379e856000000000000000000000000b31f66aa3c1e785363f0875a1b74e27b85fd66c7000000000000000000000000b97ef9ef8734c71904d8002f8b6bc66dd9c48a6e000000000000000000000000f4003f4efbe8691b60249e6afbd307abe7758adb0000000000000000000000008d2c17fad02b7bb64139109c6533b7c2b9cadb81000000000000000000000000000000000000000000000000002386f26fc100000000000000000000000000000000000000000000000000000000000ffff15afc0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008500000000000000000000000000000000000000000000000000000000006700206ae40711b8002dc6c0f4003f4efbe8691b60249e6afbd307abe7758adb1111111254eeb25477b68fb85ed929f73a9605820000000000000000000000000000000000000000000000000000000000015afcb31f66aa3c1e785363f0875a1b74e27b85fd66c7000000000000000000000000000000000000000000000000000000cfee7c08";

        vm.expectRevert(IStrategy.Strategy__SwapFailed.selector);
        IStrategy(strategy).swap(_convertHexStringToBytes(b));
    }

    function _convertHexStringToBytes(string memory hexString) internal pure returns (bytes memory) {
        bytes memory bytesString = bytes(hexString);
        require(bytesString.length % 2 == 0, "convertHexStringToBytes: invalid hex string");
        bytes memory result = new bytes(bytesString.length / 2);
        for (uint256 i = 0; i < bytesString.length; i += 2) {
            uint8 b1 = uint8(bytesString[i]);
            uint8 b2 = uint8(bytesString[i + 1]);
            require(
                b1 >= 48 && b1 <= 57 || b1 >= 65 && b1 <= 70 || b1 >= 97 && b1 <= 102,
                "convertHexStringToBytes: invalid hex string"
            );
            require(
                b2 >= 48 && b2 <= 57 || b2 >= 65 && b2 <= 70 || b2 >= 97 && b2 <= 102,
                "convertHexStringToBytes: invalid hex string"
            );
            uint8 r = uint8(b1 >= 97 ? b1 - 87 : b1 >= 65 ? b1 - 55 : b1 - 48);
            r *= 16;
            r += uint8(b2 >= 97 ? b2 - 87 : b2 >= 65 ? b2 - 55 : b2 - 48);
            result[i / 2] = bytes1(r);
        }
        return result;
    }

    function test_RebalanceAmounts() external {
        uint256 amountX = 1e24;
        uint256 amountY = 1e18;

        deal(wavax, strategy, amountX);
        deal(usdc, strategy, amountY);

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory desiredL = new uint256[](3);
        (desiredL[0], desiredL[1], desiredL[2]) = (30e6, 60e6, 30e6);

        vm.startPrank(owner);
        IStrategy(strategy).rebalance(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, desiredL, 1e18, 1e18
        );

        desiredL = new uint256[](5);

        (desiredL[0], desiredL[1], desiredL[2], desiredL[3], desiredL[4]) = (10e6, 20e6, 60e6, 20e6, 10e6);

        IStrategy(strategy).rebalance(
            uint24(activeId) - 2, uint24(activeId) + 2, uint24(activeId), 0, desiredL, 1e18, 1e18
        );
        vm.stopPrank();

        uint256[] memory amounts = new uint256[](5);

        for (uint256 i = 0; i < 5; i++) {
            amounts[i] = ILBToken(wavax_usdc_20bp).balanceOf(strategy, activeId - 2 + i);
        }

        assertApproxEqRel(amounts[0] * 2, amounts[1], 1e16, "test_RebalanceAmounts::1");
        assertApproxEqRel(amounts[4] * 2, amounts[3], 1e16, "test_RebalanceAmounts::2");

        assertApproxEqRel(
            amounts[2], amounts[0] + amounts[1] + amounts[3] + amounts[4], 1e16, "test_RebalanceAmounts::3"
        );
    }

    function test_RebalanceFar() external {
        uint256 amountX = 1e24;
        uint256 amountY = 1e18;

        deal(wavax, strategy, amountX);
        deal(usdc, strategy, amountY);

        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();

        uint256[] memory desiredL = new uint256[](3);
        (desiredL[0], desiredL[1], desiredL[2]) = (20e6, 40e6, 20e6);

        vm.startPrank(owner);
        IStrategy(strategy).rebalance(
            uint24(activeId) - 1, uint24(activeId) + 1, uint24(activeId), 0, desiredL, 1e18, 1e18
        );

        IStrategy(strategy).rebalance(
            uint24(activeId) - 100, uint24(activeId) - 98, uint24(activeId), 0, desiredL, 1e18, 1e18
        );
        vm.stopPrank();

        for (uint256 i = 0; i < 3; i++) {
            uint256 amount = ILBToken(wavax_usdc_20bp).balanceOf(strategy, activeId - 100 + i);
            assertApproxEqRel(amount, desiredL[i], 1e14, "test_RebalanceFar::1");
        }
    }

    function test_revert_InvalidAmountsLength() external {
        vm.expectRevert(IStrategy.Strategy__InvalidAmountsLength.selector);
        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 51, 0, type(uint24).max, new uint256[](0), 1e18, 1e18);
    }

    function test_revert_RangeTooWide() external {
        vm.expectRevert(IStrategy.Strategy__RangeTooWide.selector);
        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 51, 0, type(uint24).max, new uint256[](52), 1e18, 1e18);
    }

    function test_revert_MaxAmountExceededY() external {
        uint256[] memory desiredL = new uint256[](2);
        (desiredL[0], desiredL[1]) = (10e6, 10e6 + 1);

        deal(usdc, strategy, 20e6);

        vm.expectRevert(IStrategy.Strategy__MaxAmountExceeded.selector);
        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 1, 2, type(uint24).max, desiredL, 0, 1e18);

        (desiredL[0], desiredL[1]) = (10e6, 10e6);

        vm.prank(owner);
        IStrategy(strategy).rebalance(0, 1, 2, type(uint24).max, desiredL, 0, 1e18);
    }

    function test_revert_MaxAmountExceededX() external {
        (,, uint256 activeId) = ILBPair(wavax_usdc_20bp).getReservesAndId();
        uint256 price = router.getPriceFromId(ILBPair(wavax_usdc_20bp), uint24(activeId));

        uint256[] memory desiredL = new uint256[](2);
        (desiredL[0], desiredL[1]) = (price * 1e18 >> 128, price * 1e18 >> 128);

        uint256 wavaxAmount = (desiredL[0] << 128) / price + (desiredL[1] << 128) / price;

        deal(wavax, strategy, wavaxAmount - 1);

        vm.expectRevert(IStrategy.Strategy__MaxAmountExceeded.selector);
        vm.prank(owner);
        IStrategy(strategy).rebalance(1, 2, 0, type(uint24).max, desiredL, 1e18, 0);

        deal(wavax, strategy, wavaxAmount);

        vm.prank(owner);
        IStrategy(strategy).rebalance(1, 2, 0, type(uint24).max, desiredL, 1e18, 0);
    }
}
