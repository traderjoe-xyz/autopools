// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import "../src/VaultFactory.sol";
import "../src/SimpleVault.sol";
import "../src/OracleVault.sol";
import "../src/Strategy.sol";
import "../test/mocks/MockAggregator.sol";

contract TestUpgradeFactory is Test {
    address constant wnative = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    VaultFactory constant factory = VaultFactory(0xBAF3af45a51b89667066917350F504ae9B8d8Ad5);
    address constant proxyAdmin = 0x845d5ddd190296875caA26777C008D0b33783F4a;
    address constant multisig = 0xf1ec4E41B49582aF7E00D6525AF78111F37b94a8;

    address constant simpleVaultImplementation = 0x86Dd2A03dD16FAA01F83d78c803EfD952ac4EECa;
    address constant oracleVaultImplementation = 0x502722Ef70908b1Cbf153c4cacf82fd2479E40fe;
    address constant strategyImplementation = 0xe0A67dd2D10ec4985ca1db27637dC0Cc8726e9e7;

    address constant oracleVault0 = 0x84F7F975d914Ad78e3ceEa68C01c168E4CD6C2A2;
    address constant strategy0 = 0x274e9cF707FE0EF7797974B29f06c84bc72bceA1;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("arbitrum_one"), 74_956_420);
    }

    function test_UpgradeFactory() public {
        VaultFactory newImplentation = new VaultFactory(wnative);

        vm.prank(multisig);
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(factory))),
            address(newImplentation),
            abi.encodeWithSignature("initialize(address)", multisig)
        );

        assertEq(factory.getWNative(), wnative, "test_UpgradeFactory::1");
        assertEq(factory.getNumberOfVaults(IVaultFactory.VaultType.None), 0, "test_UpgradeFactory::2");
        assertEq(factory.getNumberOfVaults(IVaultFactory.VaultType.Simple), 0, "test_UpgradeFactory::3");
        assertEq(factory.getNumberOfVaults(IVaultFactory.VaultType.Oracle), 1, "test_UpgradeFactory::4");
        assertEq(factory.getVaultAt(IVaultFactory.VaultType.Oracle, 0), oracleVault0, "test_UpgradeFactory::5");

        assertEq(factory.getNumberOfStrategies(IVaultFactory.StrategyType.None), 0, "test_UpgradeFactory::6");
        assertEq(factory.getNumberOfStrategies(IVaultFactory.StrategyType.Default), 1, "test_UpgradeFactory::7");
        assertEq(factory.getStrategyAt(IVaultFactory.StrategyType.Default, 0), strategy0, "test_UpgradeFactory::8");

        assertEq(factory.getVaultImplementation(IVaultFactory.VaultType.None), address(0), "test_UpgradeFactory::9");
        assertEq(
            factory.getVaultImplementation(IVaultFactory.VaultType.Simple),
            simpleVaultImplementation,
            "test_UpgradeFactory::10"
        );
        assertEq(
            factory.getVaultImplementation(IVaultFactory.VaultType.Oracle),
            oracleVaultImplementation,
            "test_UpgradeFactory::11"
        );

        assertEq(
            factory.getStrategyImplementation(IVaultFactory.StrategyType.None), address(0), "test_UpgradeFactory::12"
        );
        assertEq(
            factory.getStrategyImplementation(IVaultFactory.StrategyType.Default),
            strategyImplementation,
            "test_UpgradeFactory::13"
        );

        assertEq(
            uint8(factory.getVaultType(oracleVault0)), uint8(IVaultFactory.VaultType.Oracle), "test_UpgradeFactory::14"
        );
        assertEq(
            uint8(factory.getStrategyType(strategy0)),
            uint8(IVaultFactory.StrategyType.Default),
            "test_UpgradeFactory::15"
        );

        assertEq(factory.getDefaultOperator(), multisig, "test_UpgradeFactory::16");
        assertEq(factory.getFeeRecipient(), multisig, "test_UpgradeFactory::17");
    }
}
