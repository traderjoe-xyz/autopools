// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "../../src/VaultFactory.sol";
import "../../src/SimpleVault.sol";
import "../../src/OracleVault.sol";
import "../../src/Strategy.sol";
import "../../test/mocks/MockAggregator.sol";

contract UpdateImplementation is Script {
    IVaultFactory constant factory = IVaultFactory(0xECe167a8623D5ab7f8568842d0fC7dAa422467d6);

    function run() public returns (address oracleVaultImplementation, address simpleVaultImplementation) {
        // vm.createSelectFork(stdChains["avalanche"].rpcUrl, 26_179_802);
        vm.createSelectFork(vm.rpcUrl("fuji"));

        uint256 deployerPrivateKey = vm.envUint("DEPLOY_PRIVATE_KEY");

        /**
         * Start broadcasting the transaction to the network.
         */
        vm.startBroadcast(deployerPrivateKey);

        oracleVaultImplementation = address(new OracleVault(factory));
        simpleVaultImplementation = address(new SimpleVault(factory));

        factory.setVaultImplementation(IVaultFactory.VaultType.Simple, simpleVaultImplementation);
        factory.setVaultImplementation(IVaultFactory.VaultType.Oracle, oracleVaultImplementation);

        vm.stopBroadcast();
        /**
         * Stop broadcasting the transaction to the network.
         */
    }
}
