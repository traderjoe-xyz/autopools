// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "joe-v2/interfaces/ILBFactory.sol";

import "./mocks/MockAggregator.sol";
import "../src/VaultFactory.sol";
import "../src/SimpleVault.sol";
import "../src/OracleVault.sol";
import "../src/CustomOracleVault.sol";
import "../src/Strategy.sol";

contract TestHelper is Test {
    address constant wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address constant usdc = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address constant usdt = 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7;
    address constant joe = 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;

    address wavax_usdc_20bp;
    address usdt_usdc_1bp;
    address joe_wavax_15bp;

    address immutable owner = makeAddr("OWNER");
    address immutable alice = makeAddr("ALICE");
    address immutable bob = makeAddr("BOB");

    VaultFactory factory;
    ILBFactory lbFactory = ILBFactory(0x8e42f2F4101563bF679975178e880FD87d3eFd4e);

    address vault;
    address strategy;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("avalanche"), 28_400_135);

        address implementation = address(new VaultFactory(wavax));
        factory = VaultFactory(address(new TransparentUpgradeableProxy(implementation, address(1), "")));

        factory.initialize(owner);

        vm.startPrank(owner);
        factory.setVaultImplementation(IVaultFactory.VaultType.Simple, address(new SimpleVault(factory)));
        factory.setVaultImplementation(IVaultFactory.VaultType.Oracle, address(new OracleVault(factory)));
        factory.setVaultImplementation(IVaultFactory.VaultType.CustomOracle, address(new CustomOracleVault(factory)));

        factory.setStrategyImplementation(IVaultFactory.StrategyType.Default, address(new Strategy(factory)));
        vm.stopPrank();

        address factoryOwner = lbFactory.owner();

        vm.startPrank(factoryOwner);
        wavax_usdc_20bp = address(lbFactory.createLBPair(IERC20(wavax), IERC20(usdc), 8_376_279, 20)); // 20 usdc per 1 wavax
        usdt_usdc_1bp = address(lbFactory.createLBPair(IERC20(usdt), IERC20(usdc), 1 << 23, 1)); // 1 usdc per 1 usdt
        joe_wavax_15bp = address(lbFactory.createLBPair(IERC20(joe), IERC20(wavax), 8_386_147, 15)); // 0.025 wavax per 1 joe
        vm.stopPrank();
    }

    function depositToVault(address newVault, address from, uint256 amountX, uint256 amountY) public {
        IERC20Upgradeable tokenX = IBaseVault(newVault).getTokenX();
        IERC20Upgradeable tokenY = IBaseVault(newVault).getTokenY();

        deal(address(tokenX), from, amountX);
        deal(address(tokenY), from, amountY);

        // use `prank` instead of `starPrank` to allow revert anywhere and allow to skip the active prank error
        vm.prank(from);
        tokenX.approve(newVault, amountX);

        vm.prank(from);
        tokenY.approve(newVault, amountY);

        vm.prank(from);
        IBaseVault(newVault).deposit(amountX, amountY);
    }

    function depositNativeToVault(address newVault, address from, uint256 amountX, uint256 amountY) public {
        IERC20Upgradeable tokenX = IBaseVault(newVault).getTokenX();
        IERC20Upgradeable tokenY = IBaseVault(newVault).getTokenY();

        bool isX = address(tokenX) == wavax;

        if (isX) {
            vm.deal(from, amountX);
            deal(address(tokenY), from, amountY);
        } else {
            deal(address(tokenX), from, amountX);
            vm.deal(from, amountY);
        }

        if (isX) {
            vm.prank(from);
            tokenY.approve(newVault, amountY);

            vm.prank(from);
            IBaseVault(newVault).depositNative{value: amountX}(amountX, amountY);
        } else {
            vm.prank(from);
            tokenX.approve(newVault, amountX);

            vm.prank(from);
            IBaseVault(newVault).depositNative{value: amountY}(amountX, amountY);
        }
    }

    function linkVaultToStrategy(address newVault, address newStrategy) public {
        vm.prank(owner);
        factory.linkVaultToStrategy(IBaseVault(newVault), newStrategy);
    }
}
