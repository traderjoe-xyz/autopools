// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {ImmutableClone} from "joe-v2/libraries/ImmutableClone.sol";
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
 * The vaults are deployed using the ImmutableClone library that allows to deploy a clone of a contract
 * and initialize it with immutable data.
 * Two vaults are available:
 * - SimpleVault: This vault is used to interact with pairs where one of the tokens has no oracle. Deposits need to be
 *                made in the same ratio as the vault's current balance.
 * - OracleVault: This vault is used to interact with pairs where both tokens have an oracle. Deposits don't need to
 *                be made in the same ratio as the vault's current balance.
 * Only one strategy is available:
 * - Strategy: This strategy allows the operator to rebalance and withdraw with no real limitation.
 */
contract VaultFactory is IVaultFactory, Ownable2StepUpgradeable {
    using StringsUpgradeable for uint256;

    address private immutable _wnative;

    mapping(VaultType => address[]) private _vaults;
    mapping(StrategyType => address[]) private _strategies;

    mapping(address => VaultType) private _vaultType;
    mapping(address => StrategyType) private _strategyType;

    mapping(VaultType => address) private _vaultImplementation;
    mapping(StrategyType => address) private _strategyImplementation;

    address private _feeRecipient;
    address private _defaultOperator;

    /**
     * @dev Modifier to check if the type id is valid.
     * @param typeId The type id to check.
     */
    modifier isValidType(uint8 typeId) {
        if (typeId == 0) revert VaultFactory__InvalidType();

        _;
    }

    /**
     * @dev Constructor of the contract.
     * @param wnative The address of the wrapped native token.
     */
    constructor(address wnative) {
        _disableInitializers();

        // safety check
        IERC20Upgradeable(wnative).balanceOf(address(this));

        _wnative = wnative;
    }

    /**
     * @dev Initialize the contract.
     * @param owner The address of the owner of the contract.
     */
    function initialize(address owner) public initializer {
        if (owner == address(0)) revert VaultFactory__InvalidOwner();

        __Ownable2Step_init();
        _transferOwnership(owner);

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
     * @notice Returns the type of the vault at the given address.
     * @dev Returns 0 (VaultType.None) if the vault doesn't exist.
     * @param vault The address of the vault.
     * @return The type of the vault.
     */
    function getVaultType(address vault) external view override returns (VaultType) {
        return _vaultType[vault];
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
     * @notice Returns the type of the strategy at the given address.
     * @dev Returns 0 (StrategyType.None) if the strategy doesn't exist.
     * @param strategy The address of the strategy.
     * @return The type of the strategy.
     */
    function getStrategyType(address strategy) external view override returns (StrategyType) {
        return _strategyType[strategy];
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

    function batchRedeemQueuedWithdrawals(
        address[] calldata vaults,
        uint256[] calldata rounds,
        bool[] calldata withdrawNative
    ) external override {
        if (vaults.length != rounds.length || vaults.length != withdrawNative.length) {
            revert VaultFactory__InvalidLength();
        }

        for (uint256 i; i < vaults.length;) {
            if (withdrawNative[i]) IBaseVault(vaults[i]).redeemQueuedWithdrawalNative(rounds[i], msg.sender);
            else IBaseVault(vaults[i]).redeemQueuedWithdrawal(rounds[i], msg.sender);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Sets the address of the vault implementation of the given type.
     * @param vType The type of the vault. (0: SimpleVault, 1: OracleVault)
     * @param vaultImplementation The address of the vault implementation.
     */
    function setVaultImplementation(VaultType vType, address vaultImplementation) external override onlyOwner {
        _setVaultImplementation(vType, vaultImplementation);
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
        _setStrategyImplementation(sType, strategyImplementation);
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
     * @notice Sets the pending AUM annual fee of the given vault's strategy.
     * @param vault The address of the vault.
     * @param pendingAumAnnualFee The pending AUM annual fee.
     */
    function setPendingAumAnnualFee(IBaseVault vault, uint16 pendingAumAnnualFee) external override onlyOwner {
        vault.getStrategy().setPendingAumAnnualFee(pendingAumAnnualFee);
    }

    /**
     * @notice Resets the pending AUM annual fee of the given vault's strategy.
     * @param vault The address of the vault.
     */
    function resetPendingAumAnnualFee(IBaseVault vault) external override onlyOwner {
        vault.getStrategy().resetPendingAumAnnualFee();
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
        if (dataFeedX.decimals() != dataFeedY.decimals()) revert VaultFactory__InvalidDecimals();

        address tokenX = address(lbPair.getTokenX());
        address tokenY = address(lbPair.getTokenY());

        vault = _createOracleVault(lbPair, tokenX, tokenY, dataFeedX, dataFeedY);
        strategy = _createDefaultStrategy(vault, lbPair, tokenX, tokenY);

        _linkVaultToStrategy(IBaseVault(vault), strategy);
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
        address tokenX = address(lbPair.getTokenX());
        address tokenY = address(lbPair.getTokenY());

        vault = _createSimpleVault(lbPair, tokenX, tokenY);
        strategy = _createDefaultStrategy(vault, lbPair, tokenX, tokenY);

        _linkVaultToStrategy(IBaseVault(vault), strategy);
    }

    /**
     * @notice Creates a new simple vault for the given LBPair.
     * @param lbPair The address of the LBPair.
     * @return vault The address of the new vault.
     */
    function createSimpleVault(ILBPair lbPair) external override onlyOwner returns (address vault) {
        address tokenX = address(lbPair.getTokenX());
        address tokenY = address(lbPair.getTokenY());

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
        address tokenX = address(lbPair.getTokenX());
        address tokenY = address(lbPair.getTokenY());

        return _createOracleVault(lbPair, tokenX, tokenY, dataFeedX, dataFeedY);
    }

    /**
     * @notice Creates a new default strategy for the given vault.
     * @param vault The address of the vault.
     * @return strategy The address of the new strategy.
     */
    function createDefaultStrategy(IBaseVault vault) external override onlyOwner returns (address strategy) {
        ILBPair lbPair = vault.getPair();
        address tokenX = address(lbPair.getTokenX());
        address tokenY = address(lbPair.getTokenY());

        return _createDefaultStrategy(address(vault), lbPair, tokenX, tokenY);
    }

    /**
     * @notice Links the given vault to the given strategy.
     * @param vault The address of the vault.
     * @param strategy The address of the strategy.
     */
    function linkVaultToStrategy(IBaseVault vault, address strategy) external override onlyOwner {
        if (_strategyType[strategy] == StrategyType.None) revert VaultFactory__InvalidStrategy();

        _linkVaultToStrategy(vault, strategy);
    }

    /**
     * @notice Sets the whitelist state of the given vault.
     * @param vault The address of the vault.
     * @param isWhitelisted The whitelist state.
     */
    function setWhitelistState(IBaseVault vault, bool isWhitelisted) external override onlyOwner {
        vault.setWhitelistState(isWhitelisted);
    }

    /**
     * @notice Adds addresses to the whitelist of the given vault.
     * @param vault The address of the vault.
     * @param addresses The addresses to add.
     */
    function addToWhitelist(IBaseVault vault, address[] calldata addresses) external override onlyOwner {
        vault.addToWhitelist(addresses);
    }

    /**
     * @notice Removes addresses from the whitelist of the given vault.
     * @param vault The address of the vault.
     * @param addresses The addresses to remove.
     */
    function removeFromWhitelist(IBaseVault vault, address[] calldata addresses) external override onlyOwner {
        vault.removeFromWhitelist(addresses);
    }

    /**
     * @notice Pauses the deposits of the given vault.
     * @param vault The address of the vault.
     */
    function pauseDeposits(IBaseVault vault) external override onlyOwner {
        vault.pauseDeposits();
    }

    /**
     * @notice Resumes the deposits of the given vault.
     * @param vault The address of the vault.
     */
    function resumeDeposits(IBaseVault vault) external override onlyOwner {
        vault.resumeDeposits();
    }

    /**
     * @notice Sets the vault to emergency mode.
     * @param vault The address of the vault.
     */
    function setEmergencyMode(IBaseVault vault) external override onlyOwner {
        vault.setEmergencyMode();
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
        override
        onlyOwner
    {
        vault.recoverERC20(token, recipient, amount);
    }

    /**
     * @dev Sets the vault implementation of the given type.
     * @param vType The type of the vault.
     * @param vaultImplementation The address of the vault implementation.
     */
    function _setVaultImplementation(VaultType vType, address vaultImplementation) internal {
        _vaultImplementation[vType] = vaultImplementation;

        emit VaultImplementationSet(vType, vaultImplementation);
    }

    /**
     * @dev Sets the strategy implementation of the given type.
     * @param sType The type of the strategy.
     * @param strategyImplementation The address of the strategy implementation.
     */
    function _setStrategyImplementation(StrategyType sType, address strategyImplementation) internal {
        _strategyImplementation[sType] = strategyImplementation;

        emit StrategyImplementationSet(sType, strategyImplementation);
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
        else if (vType == VaultType.Oracle) vName = "Oracle";
        else revert VaultFactory__InvalidType();

        return string(abi.encodePacked("Automated Pool Token - ", vName, " Vault #", vaultId.toString()));
    }

    /**
     * @dev Internal function to create a new simple vault.
     * @param lbPair The address of the LBPair.
     * @param tokenX The address of token X.
     * @param tokenY The address of token Y.
     */
    function _createSimpleVault(ILBPair lbPair, address tokenX, address tokenY) internal returns (address vault) {
        uint8 decimalsX = IERC20MetadataUpgradeable(tokenX).decimals();
        uint8 decimalsY = IERC20MetadataUpgradeable(tokenY).decimals();

        bytes memory vaultImmutableData = abi.encodePacked(lbPair, tokenX, tokenY, decimalsX, decimalsY);

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
        if (IOracleVault(vault).getPrice() == 0) revert VaultFactory__InvalidOraclePrice();
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
    ) private isValidType(uint8(vType)) returns (address vault) {
        address vaultImplementation = _vaultImplementation[vType];
        if (vaultImplementation == address(0)) revert VaultFactory__VaultImplementationNotSet(vType);

        uint256 vaultId = _vaults[vType].length;

        bytes32 salt = keccak256(abi.encodePacked(vType, vaultId));
        vault = ImmutableClone.cloneDeterministic(vaultImplementation, vaultImmutableData, salt);

        _vaults[vType].push(vault);
        _vaultType[vault] = vType;

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
        uint256 binStep = lbPair.getBinStep();
        bytes memory strategyImmutableData = abi.encodePacked(vault, lbPair, tokenX, tokenY, uint16(binStep));

        return _createStrategy(StrategyType.Default, address(vault), lbPair, strategyImmutableData);
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
        isValidType(uint8(sType))
        returns (address strategy)
    {
        address strategyImplementation = _strategyImplementation[sType];
        if (strategyImplementation == address(0)) revert VaultFactory__StrategyImplementationNotSet(sType);

        uint256 strategyId = _strategies[sType].length;

        bytes32 salt = keccak256(abi.encodePacked(sType, strategyId));
        strategy = ImmutableClone.cloneDeterministic(strategyImplementation, strategyImmutableData, salt);

        _strategies[sType].push(strategy);
        _strategyType[strategy] = sType;

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
        if (feeRecipient == address(0)) revert VaultFactory__InvalidFeeRecipient();

        _feeRecipient = feeRecipient;

        emit FeeRecipientSet(msg.sender, feeRecipient);
    }

    /**
     * @dev Internal function to link the given vault to the given strategy.
     * @param vault The address of the vault.
     * @param strategy The address of the strategy.
     */
    function _linkVaultToStrategy(IBaseVault vault, address strategy) internal {
        vault.setStrategy(IStrategy(strategy));
    }

    /**
     * @dev This is a gap filler to allow us to add new variables in the future without breaking
     *      the storage layout of the contract.
     */
    uint256[42] private __gap;
}
