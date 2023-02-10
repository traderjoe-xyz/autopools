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

contract VaultFactory is IVaultFactory, Ownable2StepUpgradeable {
    using StringsUpgradeable for uint256;

    address private immutable _wnative;

    mapping(VaultType => address[]) private _vaults;
    mapping(StrategyType => address[]) private _strategies;

    mapping(address => address) private _vaultToCurrentStrategy;

    mapping(VaultType => address) private _vaultImplementation;
    mapping(StrategyType => address) private _strategyImplementation;

    address private _feeRecipient;
    address private _defaultOperator;

    constructor(address wnative) {
        _disableInitializers();

        _wnative = wnative;
    }

    function initialize() public initializer {
        __Ownable2Step_init();

        _setDefaultOperator(msg.sender);
        _setFeeRecipient(msg.sender);
    }

    function getWNative() external view override returns (address) {
        return _wnative;
    }

    function getVaultAt(VaultType vType, uint256 index) external view override returns (address) {
        return _vaults[vType][index];
    }

    function getStrategyAt(StrategyType sType, uint256 index) external view override returns (address) {
        return _strategies[sType][index];
    }

    function getNumberOfVaults(VaultType vType) external view override returns (uint256) {
        return _vaults[vType].length;
    }

    function getNumberOfStrategies(StrategyType sType) external view override returns (uint256) {
        return _strategies[sType].length;
    }

    function getDefaultOperator() external view override returns (address) {
        return _defaultOperator;
    }

    function getFeeRecipient() external view override returns (address) {
        return _feeRecipient;
    }

    function getVaultImplementation(VaultType vType) external view override returns (address) {
        return _vaultImplementation[vType];
    }

    function getStrategyImplementation(StrategyType sType) external view override returns (address) {
        return _strategyImplementation[sType];
    }

    function setVaultImplementation(VaultType vType, address vaultImplementation) external override onlyOwner {
        _vaultImplementation[vType] = vaultImplementation;

        emit VaultImplementationSet(vType, vaultImplementation);
    }

    function setStrategyImplementation(StrategyType sType, address strategyImplementation)
        external
        override
        onlyOwner
    {
        _strategyImplementation[sType] = strategyImplementation;

        emit StrategyImplementationSet(sType, strategyImplementation);
    }

    function setDefaultOperator(address defaultOperator) external override onlyOwner {
        _setDefaultOperator(defaultOperator);
    }

    function setFeeRecipient(address feeRecipient) external override onlyOwner {
        _setFeeRecipient(feeRecipient);
    }

    function createOracleVaultAndSimpleStrategy(ILBPair lbPair, IAggregatorV3 dataFeedX, IAggregatorV3 dataFeedY)
        external
        override
        onlyOwner
        returns (address vault, address strategy)
    {
        address tokenX = address(lbPair.tokenX());
        address tokenY = address(lbPair.tokenY());

        vault = _createOracleVault(lbPair, tokenX, tokenY, dataFeedX, dataFeedY);
        strategy = _createSimpleStrategy(vault, lbPair, tokenX, tokenY);

        _linkVaultToStrategy(vault, strategy);
    }

    function createSimpleVaultAndSimpleStrategy(ILBPair lbPair)
        external
        override
        onlyOwner
        returns (address vault, address strategy)
    {
        address tokenX = address(lbPair.tokenX());
        address tokenY = address(lbPair.tokenY());

        vault = _createSimpleVault(lbPair, tokenX, tokenY);
        strategy = _createSimpleStrategy(vault, lbPair, tokenX, tokenY);

        _linkVaultToStrategy(vault, strategy);
    }

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

    function createSimpleVault(ILBPair lbPair) external override onlyOwner returns (address vault) {
        address tokenX = address(lbPair.tokenX());
        address tokenY = address(lbPair.tokenY());

        return _createSimpleVault(lbPair, tokenX, tokenY);
    }

    function createSimpleStrategy(address vault) external onlyOwner returns (address strategy) {
        ILBPair lbPair = IBaseVault(vault).getPair();
        address tokenX = address(lbPair.tokenX());
        address tokenY = address(lbPair.tokenY());

        return _createSimpleStrategy(vault, lbPair, tokenX, tokenY);
    }

    function linkVaultToStrategy(address vault, address strategy) external onlyOwner {
        if (strategy == address(0)) revert VaultFactory__ZeroAddress();

        _linkVaultToStrategy(vault, strategy);
    }

    function pauseVault(address vault) external onlyOwner {
        _linkVaultToStrategy(vault, address(0));
    }

    function recoverERC20(IBaseVault vault, address token, address recipient, uint256 amount) external onlyOwner {
        vault.recoverERC20(token, recipient, amount);
    }

    function _getName(VaultType vType, ILBPair lbPair, address tokenX, address tokenY)
        internal
        view
        returns (string memory)
    {
        string memory prefix;
        if (vType == VaultType.Simple) {
            prefix = "LBSimpleVault:";
        } else if (vType == VaultType.Oracle) {
            prefix = "LBOracleVault:";
        } else {
            revert VaultFactory__InvalidVaultType();
        }

        return string(
            abi.encodePacked(
                prefix,
                IERC20MetadataUpgradeable(tokenX).symbol(),
                "/",
                IERC20MetadataUpgradeable(tokenY).symbol(),
                "-",
                uint256(lbPair.feeParameters().binStep).toString(),
                "bp"
            )
        );
    }

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

        return _createVault(VaultType.Oracle, lbPair, tokenX, tokenY, vaultImmutableData);
    }

    function _createSimpleVault(ILBPair lbPair, address tokenX, address tokenY) internal returns (address vault) {
        uint8 decimalsX = IERC20MetadataUpgradeable(tokenX).decimals();
        uint8 decimalsY = IERC20MetadataUpgradeable(tokenY).decimals();

        bytes memory vaultImmutableData = abi.encodePacked(lbPair, tokenX, tokenY, decimalsX, decimalsY);
        return _createVault(VaultType.Simple, lbPair, tokenX, tokenY, vaultImmutableData);
    }

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

        IBaseVault(vault).initialize(_getName(vType, lbPair, tokenX, tokenY), "APT");

        emit VaultCreated(vType, vault, lbPair, vaultId, tokenX, tokenY);
    }

    function _createSimpleStrategy(address vault, ILBPair lbPair, address tokenX, address tokenY)
        internal
        returns (address strategy)
    {
        bytes memory strategyImmutableData = abi.encodePacked(vault, lbPair, tokenX, tokenY);
        return _createStrategy(StrategyType.Simple, vault, lbPair, strategyImmutableData);
    }

    function _createStrategy(StrategyType sType, address vault, ILBPair lbPair, bytes memory strategyImmutableData)
        internal
        returns (address strategy)
    {
        address strategyImplementation = _strategyImplementation[sType];
        if (strategyImplementation == address(0)) revert VaultFactory__StrategyImplementationNotSet(sType);

        uint256 strategyId = _strategies[sType].length;

        strategy = ClonesWithImmutableArgs.clone(strategyImplementation, strategyImmutableData);
        _strategies[sType].push(strategy);

        emit StrategyCreated(sType, strategy, vault, lbPair, strategyId);
    }

    function _setDefaultOperator(address defaultOperator) internal {
        _defaultOperator = defaultOperator;

        emit DefaultOperatorSet(msg.sender, defaultOperator);
    }

    function _setFeeRecipient(address feeRecipient) internal {
        _feeRecipient = feeRecipient;

        emit FeeRecipientSet(msg.sender, feeRecipient);
    }

    function _linkVaultToStrategy(address vault, address strategy) internal {
        _vaultToCurrentStrategy[vault] = strategy;

        if (strategy == address(0)) {
            IBaseVault(vault).pauseVault();
        } else {
            IBaseVault(vault).setStrategy(IStrategy(strategy));
        }
    }
}
