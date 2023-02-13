// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "openzeppelin-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ILBPair} from "joe-v2/interfaces/ILBPair.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {StringsUpgradeable} from "openzeppelin-upgradeable/utils/StringsUpgradeable.sol";

import {IStrategy} from "./interfaces/IStrategy.sol";
import {IBaseVault} from "./interfaces/IBaseVault.sol";
import {IOracleVault} from "./interfaces/IOracleVault.sol";
import {IVaultFactory} from "./interfaces/IVaultFactory.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";

/**
 * @title Liquidity Book Vault Factory contract
 * @author Trader Joe
 * @notice This contract is used to deploy new vaults. It is made to be used with the transparent proxy pattern.
 * The vaults are deployed using the ClonesWithImmutableArgs library that allows to deploy a clone of a contract
 * and initialize it with immutable data.
 * Two vaults are available:
 * - SimpleVault: This vault is used to interact with pairs where one of the token has no oracle. Deposits needs to be
 *                made in the same ratio as the vault's current balance.
 * - OracleVault: This vault is used to interact with pairs where both tokens have an oracle. Deposits doesn't need to
 *                be made in the same ratio as the vault's current balance.
 * Only one strategy is available:
 * - Strategy: This strategy allows the operator to deposit and withdraw funds from the vault with no real limitation.
 */
contract VaultFactory is IVaultFactory, Ownable2StepUpgradeable {
    using StringsUpgradeable for uint256;

    address private immutable _wnative;

    mapping(VaultType => address[]) private _vaults;
    mapping(StrategyType => address[]) private _strategies;

    mapping(VaultType => address) private _vaultImplementation;
    mapping(StrategyType => address) private _strategyImplementation;

    address private _feeRecipient;
    address private _defaultOperator;

    /**
     * @dev Constructor of the contract.
     * @param wnative The address of the wrapped native token.
     */
    constructor(address wnative) {
        _disableInitializers();

        _wnative = wnative;
    }

    /**
     * @dev Initialize the contract.
     * @param owner The address of the owner of the contract.
     */
    function initialize(address owner) external initializer {
        __Ownable2Step_init();

        if (owner != msg.sender) _transferOwnership(owner);

        _setDefaultOperator(owner);
        _setFeeRecipient(owner);
    }

    /**
     * @notice Returns the address of the wrapped native token.
     * @return The address of the wrapped native token.
     */
    function getWNative() external view override returns (address) {
        return _wnative;
    }

    /**
     * @notice Returns the address of the vault at the given index.
     * @param vType The type of the vault. (0: SimpleVault, 1: OracleVault)
     * @param index The index of the vault.
     * @return The address of the vault.
     */
    function getVaultAt(VaultType vType, uint256 index) external view override returns (address) {
        return _vaults[vType][index];
    }

    /**
     * @notice Returns the address of the strategy at the given index.
     * @param sType The type of the strategy. (0: DefaultStrategy)
     * @param index The index of the strategy.
     * @return The address of the strategy.
     */
    function getStrategyAt(StrategyType sType, uint256 index) external view override returns (address) {
        return _strategies[sType][index];
    }

    /**
     * @notice Returns the number of vaults of the given type.
     * @param vType The type of the vault. (0: SimpleVault, 1: OracleVault)
     * @return The number of vaults of the given type.
     */
    function getNumberOfVaults(VaultType vType) external view override returns (uint256) {
        return _vaults[vType].length;
    }

    /**
     * @notice Returns the number of strategies of the given type.
     * @param sType The type of the strategy. (0: DefaultStrategy)
     * @return The number of strategies of the given type.
     */
    function getNumberOfStrategies(StrategyType sType) external view override returns (uint256) {
        return _strategies[sType].length;
    }

    /**
     * @notice Returns the address of the default operator.
     * @return The address of the default operator.
     */
    function getDefaultOperator() external view override returns (address) {
        return _defaultOperator;
    }

    /**
     * @notice Returns the address of the fee recipient.
     * @return The address of the fee recipient.
     */
    function getFeeRecipient() external view override returns (address) {
        return _feeRecipient;
    }

    /**
     * @notice Returns the address of the vault implementation of the given type.
     * @param vType The type of the vault. (0: SimpleVault, 1: OracleVault)
     * @return The address of the vault implementation.
     */
    function getVaultImplementation(VaultType vType) external view override returns (address) {
        return _vaultImplementation[vType];
    }

    /**
     * @notice Returns the address of the strategy implementation of the given type.
     * @param sType The type of the strategy. (0: DefaultStrategy)
     * @return The address of the strategy implementation.
     */
    function getStrategyImplementation(StrategyType sType) external view override returns (address) {
        return _strategyImplementation[sType];
    }

    /**
     * @notice Sets the address of the vault implementation of the given type.
     * @param vType The type of the vault. (0: SimpleVault, 1: OracleVault)
     * @param vaultImplementation The address of the vault implementation.
     */
    function setVaultImplementation(VaultType vType, address vaultImplementation) external override onlyOwner {
        _vaultImplementation[vType] = vaultImplementation;

        emit VaultImplementationSet(vType, vaultImplementation);
    }

    /**
     * @notice Sets the address of the strategy implementation of the given type.
     * @param sType The type of the strategy. (0: DefaultStrategy)
     * @param strategyImplementation The address of the strategy implementation.
     */
    function setStrategyImplementation(StrategyType sType, address strategyImplementation)
        external
        override
        onlyOwner
    {
        _strategyImplementation[sType] = strategyImplementation;

        emit StrategyImplementationSet(sType, strategyImplementation);
    }

    /**
     * @notice Sets the address of the default operator.
     * @param defaultOperator The address of the default operator.
     */
    function setDefaultOperator(address defaultOperator) external override onlyOwner {
        _setDefaultOperator(defaultOperator);
    }

    /**
     * @notice Sets the address of the operator of the given strategy.
     * @param strategy The address of the strategy.
     * @param operator The address of the operator.
     */
    function setOperator(IStrategy strategy, address operator) external override onlyOwner {
        strategy.setOperator(operator);
    }

    /**
     * @notice Sets the strategist fee of the given strategy.
     * @param strategy The address of the strategy.
     * @param strategistFee The strategist fee.
     */
    function setStrategistFee(IStrategy strategy, uint256 strategistFee) external override onlyOwner {
        strategy.setStrategistFee(strategistFee);
    }

    /**
     * @notice Sets the address of the fee recipient.
     * @param feeRecipient The address of the fee recipient.
     */
    function setFeeRecipient(address feeRecipient) external override onlyOwner {
        _setFeeRecipient(feeRecipient);
    }

    /**
     * @notice Creates a new oracle vault and a default strategy for the given LBPair.
     * @dev The oracle vault will be linked to the default strategy.
     * @param lbPair The address of the LBPair.
     * @param dataFeedX The address of the data feed for token X.
     * @param dataFeedY The address of the data feed for token Y.
     * @return vault The address of the new vault.
     * @return strategy The address of the new strategy.
     */
    function createOracleVaultAndDefaultStrategy(ILBPair lbPair, IAggregatorV3 dataFeedX, IAggregatorV3 dataFeedY)
        external
        override
        onlyOwner
        returns (address vault, address strategy)
    {
        address tokenX = address(lbPair.tokenX());
        address tokenY = address(lbPair.tokenY());

        vault = _createOracleVault(lbPair, tokenX, tokenY, dataFeedX, dataFeedY);
        strategy = _createDefaultStrategy(vault, lbPair, tokenX, tokenY);

        _linkVaultToStrategy(vault, strategy);
    }

    /**
     * @notice Creates a new simple vault and a default strategy for the given LBPair.
     * @dev The simple vault will be linked to the default strategy.
     * @param lbPair The address of the LBPair.
     * @return vault The address of the new vault.
     * @return strategy The address of the new strategy.
     */
    function createSimpleVaultAndDefaultStrategy(ILBPair lbPair)
        external
        override
        onlyOwner
        returns (address vault, address strategy)
    {
        address tokenX = address(lbPair.tokenX());
        address tokenY = address(lbPair.tokenY());

        vault = _createSimpleVault(lbPair, tokenX, tokenY);
        strategy = _createDefaultStrategy(vault, lbPair, tokenX, tokenY);

        _linkVaultToStrategy(vault, strategy);
    }

    /**
     * @notice Creates a new simple vault for the given LBPair.
     * @param lbPair The address of the LBPair.
     * @return vault The address of the new vault.
     */
    function createSimpleVault(ILBPair lbPair) external override onlyOwner returns (address vault) {
        address tokenX = address(lbPair.tokenX());
        address tokenY = address(lbPair.tokenY());

        return _createSimpleVault(lbPair, tokenX, tokenY);
    }

    /**
     * @notice Creates a new oracle vault for the given LBPair.
     * @param lbPair The address of the LBPair.
     * @param dataFeedX The address of the data feed for token X.
     * @param dataFeedY The address of the data feed for token Y.
     * @return vault The address of the new vault.
     */
    function createOracleVault(ILBPair lbPair, IAggregatorV3 dataFeedX, IAggregatorV3 dataFeedY)
        external
        override
        onlyOwner
        returns (address vault)
    {
        address tokenX = address(lbPair.tokenX());
        address tokenY = address(lbPair.tokenY());

        return _createOracleVault(lbPair, tokenX, tokenY, dataFeedX, dataFeedY);
    }

    /**
     * @notice Creates a new default strategy for the given vault.
     * @param vault The address of the vault.
     * @return strategy The address of the new strategy.
     */
    function createDefaultStrategy(address vault) external onlyOwner returns (address strategy) {
        ILBPair lbPair = IBaseVault(vault).getPair();
        address tokenX = address(lbPair.tokenX());
        address tokenY = address(lbPair.tokenY());

        return _createDefaultStrategy(vault, lbPair, tokenX, tokenY);
    }

    /**
     * @notice Links the given vault to the given strategy.
     * @param vault The address of the vault.
     * @param strategy The address of the strategy.
     */
    function linkVaultToStrategy(address vault, address strategy) external onlyOwner {
        if (strategy == address(0)) revert VaultFactory__ZeroAddress();

        _linkVaultToStrategy(vault, strategy);
    }

    /**
     * @notice Pauses the given vault.
     * @param vault The address of the vault.
     */
    function pauseVault(address vault) external onlyOwner {
        IBaseVault(vault).pauseVault();
    }

    /**
     * @notice Recover ERC20 tokens from the given vault.
     * @param vault The address of the vault.
     * @param token The address of the token.
     * @param recipient The address of the recipient.
     * @param amount The amount of tokens to recover.
     */
    function recoverERC20(IBaseVault vault, IERC20Upgradeable token, address recipient, uint256 amount)
        external
        onlyOwner
    {
        vault.recoverERC20(token, recipient, amount);
    }

    /**
     * @dev Returns the name of the vault of the given type and id.
     * @param vType The type of the vault.
     * @param vaultId The id of the vault.
     * @return vName The name of the vault.
     */
    function _getName(VaultType vType, uint256 vaultId) internal pure returns (string memory) {
        string memory vName;

        if (vType == VaultType.Simple) vName = "Simple";
        else vName = "Oracle";

        return string(abi.encodePacked("Automated Pool Token - ", vName, " Vault #", vaultId.toString()));
    }

    /**
     * @dev Internal function to create a new simple vault.
     * @param lbPair The address of the LBPair.
     * @param tokenX The address of token X.
     * @param tokenY The address of token Y.
     */
    function _createSimpleVault(ILBPair lbPair, address tokenX, address tokenY) internal returns (address vault) {
        bytes memory vaultImmutableData = abi.encodePacked(lbPair, tokenX, tokenY);
        return _createVault(VaultType.Simple, lbPair, tokenX, tokenY, vaultImmutableData);
    }

    /**
     * @dev Internal function to create a new oracle vault.
     * @param lbPair The address of the LBPair.
     * @param tokenX The address of token X.
     * @param tokenY The address of token Y.
     * @param dataFeedX The address of the data feed for token X.
     * @param dataFeedY The address of the data feed for token Y.
     */
    function _createOracleVault(
        ILBPair lbPair,
        address tokenX,
        address tokenY,
        IAggregatorV3 dataFeedX,
        IAggregatorV3 dataFeedY
    ) internal returns (address vault) {
        uint8 decimalsX = IERC20MetadataUpgradeable(tokenX).decimals();
        uint8 decimalsY = IERC20MetadataUpgradeable(tokenY).decimals();

        bytes memory vaultImmutableData =
            abi.encodePacked(lbPair, tokenX, tokenY, decimalsX, decimalsY, dataFeedX, dataFeedY);

        vault = _createVault(VaultType.Oracle, lbPair, tokenX, tokenY, vaultImmutableData);

        // Safety check to ensure the oracles are set correctly
        IOracleVault(vault).getPrice();
    }

    /**
     * @dev Internal function to create a new vault of the given type.
     * @param vType The type of the vault.
     * @param lbPair The address of the LBPair.
     * @param tokenX The address of token X.
     * @param tokenY The address of token Y.
     * @param vaultImmutableData The immutable data to pass to the vault.
     */
    function _createVault(
        VaultType vType,
        ILBPair lbPair,
        address tokenX,
        address tokenY,
        bytes memory vaultImmutableData
    ) private returns (address vault) {
        address vaultImplementation = _vaultImplementation[vType];
        if (vaultImplementation == address(0)) revert VaultFactory__VaultImplementationNotSet(vType);

        uint256 vaultId = _vaults[vType].length;

        vault = ClonesWithImmutableArgs.clone(vaultImplementation, vaultImmutableData);
        _vaults[vType].push(vault);

        IBaseVault(vault).initialize(_getName(vType, vaultId), "APT");

        emit VaultCreated(vType, vault, lbPair, vaultId, tokenX, tokenY);
    }

    /**
     * @dev Internal function to create a new default strategy for the given vault.
     * @param vault The address of the vault.
     * @param lbPair The address of the LBPair.
     * @param tokenX The address of token X.
     * @param tokenY The address of token Y.
     */
    function _createDefaultStrategy(address vault, ILBPair lbPair, address tokenX, address tokenY)
        internal
        returns (address strategy)
    {
        bytes memory strategyImmutableData = abi.encodePacked(vault, lbPair, tokenX, tokenY);
        return _createStrategy(StrategyType.Default, vault, lbPair, strategyImmutableData);
    }

    /**
     * @dev Internal function to create a new strategy of the given type.
     * @param sType The type of the strategy.
     * @param vault The address of the vault.
     * @param lbPair The address of the LBPair.
     * @param strategyImmutableData The immutable data to pass to the strategy.
     */
    function _createStrategy(StrategyType sType, address vault, ILBPair lbPair, bytes memory strategyImmutableData)
        internal
        returns (address strategy)
    {
        address strategyImplementation = _strategyImplementation[sType];
        if (strategyImplementation == address(0)) revert VaultFactory__StrategyImplementationNotSet(sType);

        uint256 strategyId = _strategies[sType].length;

        strategy = ClonesWithImmutableArgs.clone(strategyImplementation, strategyImmutableData);
        _strategies[sType].push(strategy);

        IStrategy(strategy).initialize();

        emit StrategyCreated(sType, strategy, vault, lbPair, strategyId);
    }

    /**
     * @dev Internal function to set the default operator.
     * @param defaultOperator The address of the default operator.
     */
    function _setDefaultOperator(address defaultOperator) internal {
        _defaultOperator = defaultOperator;

        emit DefaultOperatorSet(msg.sender, defaultOperator);
    }

    /**
     * @dev Internal function to set the fee recipient.
     * @param feeRecipient The address of the fee recipient.
     */
    function _setFeeRecipient(address feeRecipient) internal {
        _feeRecipient = feeRecipient;

        emit FeeRecipientSet(msg.sender, feeRecipient);
    }

    /**
     * @dev Internal function to link the given vault to the given strategy.
     * @param vault The address of the vault.
     * @param strategy The address of the strategy.
     */
    function _linkVaultToStrategy(address vault, address strategy) internal {
        IBaseVault(vault).setStrategy(IStrategy(strategy));
    }

    /**
     * @dev This is a gap filler to allow us to add new variables in the future without breaking
     *      the storage layout of the contract.
     */
    uint256[43] private __gap;
}
