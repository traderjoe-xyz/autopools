// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../script/fuji/DeployFactory.s.sol";

contract DeployFactoryTest is Test {
    DeployFactory script;

    function setUp() public virtual {
        script = new DeployFactory();
    }

    function test_Deploy() external {
        DeployFactory.Contracts memory contracts = script.run();

        assertFalse(contracts.factory == address(0), "test_Deploy::1");
        assertEq(
            address(IBaseVault(contracts.oracleVaultImplementation).getFactory()), contracts.factory, "test_Deploy::2"
        );
        assertEq(
            address(IBaseVault(contracts.simpleVaultImplementation).getFactory()), contracts.factory, "test_Deploy::3"
        );
        assertEq(address(IStrategy(contracts.strategyImplementation).getFactory()), contracts.factory, "test_Deploy::4");

        vm.startPrank(contracts.proxyAdmin);
        assertEq(
            address(TransparentUpgradeableProxy(payable(contracts.factory)).admin()),
            contracts.proxyAdmin,
            "test_Deploy::5"
        );
        assertEq(
            address(TransparentUpgradeableProxy(payable(contracts.factory)).implementation()),
            contracts.factoryImplementation,
            "test_Deploy::6"
        );
        vm.stopPrank();

        assertEq(ProxyAdmin(contracts.proxyAdmin).owner(), Ownable(contracts.factory).owner(), "test_Deploy::7");
    }
}
