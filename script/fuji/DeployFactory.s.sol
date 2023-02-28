// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import "../../src/VaultFactory.sol";
import "../../src/SimpleVault.sol";
import "../../src/OracleVault.sol";
import "../../src/Strategy.sol";
import "../../test/mocks/MockAggregator.sol";

contract DeployFactory is Script {
    address constant wnative = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;

    struct Contracts {
        address factoryImplementation;
        address oracleVaultImplementation;
        address simpleVaultImplementation;
        address strategyImplementation;
        address proxyAdmin;
        address factory;
    }

    function run() public returns (Contracts memory contracts) {
        vm.createSelectFork(vm.rpcUrl("fuji"));

        uint256 deployerPrivateKey = vm.envUint("DEPLOY_PRIVATE_KEY");

        /**
         * Start broadcasting the transaction to the network.
         */
        vm.startBroadcast(deployerPrivateKey);

        contracts.proxyAdmin = address(new ProxyAdmin());
        contracts.factoryImplementation = address(new VaultFactory(wnative));

        VaultFactory factory = VaultFactory(
            address(
                new TransparentUpgradeableProxy(
                    contracts.factoryImplementation,
                    contracts.proxyAdmin,
                    abi.encodeWithSignature("initialize(address)", vm.addr(deployerPrivateKey))
                )
            )
        );

        contracts.factory = address(factory);

        contracts.oracleVaultImplementation = address(new OracleVault(factory));
        contracts.simpleVaultImplementation = address(new SimpleVault(factory));
        contracts.strategyImplementation = address(new Strategy(factory));

        factory.setVaultImplementation(IVaultFactory.VaultType.Simple, contracts.simpleVaultImplementation);
        factory.setVaultImplementation(IVaultFactory.VaultType.Oracle, contracts.oracleVaultImplementation);

        factory.setStrategyImplementation(IVaultFactory.StrategyType.Default, contracts.strategyImplementation);

        vm.stopBroadcast();
        /**
         * Stop broadcasting the transaction to the network.
         */
    }
}
