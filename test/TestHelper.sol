// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "joe-v2/interfaces/ILBRouter.sol";

import "./mocks/MockAggregator.sol";
import "../src/VaultFactory.sol";
import "../src/SimpleVault.sol";
import "../src/OracleVault.sol";
import "../src/Strategy.sol";

contract TestHelper is Test {
    address constant wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address constant usdc = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address constant usdt = 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7;
    address constant joe = 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;

    address wavax_usdc_20bp = 0xB5352A39C11a81FE6748993D586EC448A01f08b5;
    address usdt_usdc_1bp = 0x1D7A1a79e2b4Ef88D2323f3845246D24a3c20F1d;
    address joe_wavax_15bp = 0xc01961EdE437Bf0cC41D064B1a3F6F0ea6aa2a40;

    address immutable owner = makeAddr("OWNER");
    address immutable alice = makeAddr("ALICE");
    address immutable bob = makeAddr("BOB");

    VaultFactory factory;
    ILBRouter router = ILBRouter(0xE3Ffc583dC176575eEA7FD9dF2A7c65F7E23f4C3);

    address vault;
    address strategy;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("avalanche"), 26_179_802);

        address implementation = address(new VaultFactory(wavax));
        factory = VaultFactory(address(new TransparentUpgradeableProxy(implementation, address(1), "")));

        factory.initialize(owner);

        vm.startPrank(owner);
        factory.setVaultImplementation(IVaultFactory.VaultType.Simple, address(new SimpleVault(factory)));
        factory.setVaultImplementation(IVaultFactory.VaultType.Oracle, address(new OracleVault(factory)));

        factory.setStrategyImplementation(IVaultFactory.StrategyType.Default, address(new Strategy(factory)));
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
