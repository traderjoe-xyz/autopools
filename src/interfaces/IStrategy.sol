// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ILBPair} from "joe-v2/interfaces/ILBPair.sol";

import {IVaultFactory} from "./IVaultFactory.sol";

interface IStrategy {
    error Strategy__OnlyFactory();
    error Strategy__OnlyVault();
    error Strategy__OnlyOperators();
    error Strategy__InvalidDistribution();
    error Strategy__ZeroAmounts();
    error Strategy__SwapFailed();
    error Strategy__InvalidData();
    error Strategy__InvalidDstToken();
    error Strategy__InvalidReceiver();
    error Strategy__InvalidPrice();
    error Strategy__InvalidRange();
    error Strategy__InvalidRemovedRange();
    error Strategy__InvalidAddedRange();
    error Strategy__InvalidFee();

    event OperatorSet(address operator);

    event StrategistFeeSet(uint256 fee);

    event FeesCollected(
        address indexed sender, address indexed feeRecipient, uint256 vaultX, uint256 vaultY, uint256 feeX, uint256 feeY
    );

    function getFactory() external view returns (IVaultFactory);

    function getVault() external pure returns (address);

    function getPair() external pure returns (ILBPair);

    function getTokenX() external pure returns (IERC20Upgradeable);

    function getTokenY() external pure returns (IERC20Upgradeable);

    function getRange() external view returns (uint24 low, uint24 upper);

    function getStrategistFee() external view returns (uint256 fee);

    function getOperator() external view returns (address);

    function getBalances() external view returns (uint256 amountX, uint256 amountY);

    function getPendingFees() external view returns (uint256 amountX, uint256 amountY);

    function initialize() external;

    function withdraw(uint256 shares, uint256 totalSupply, address to)
        external
        returns (uint256 amountX, uint256 amountY);

    function depositToLB(
        uint24 addedLower,
        uint24 addedUpper,
        uint256[] calldata distributionX,
        uint256[] calldata distributionY,
        uint256 percentageToAddX,
        uint256 percentageToAddY
    ) external;

    function withdrawFromLB(uint24 removedLow, uint24 removedUpper, uint256 percentageToRemove) external;

    function rebalanceFromLB(
        uint24 removedLow,
        uint24 removedUpper,
        uint256 percentageToRemove,
        uint24 addedLower,
        uint24 addedUpper,
        uint256[] calldata distributionX,
        uint256[] calldata distributionY,
        uint256 percentageToAddX,
        uint256 percentageToAddY
    ) external;

    function collectFees() external;

    function swap(bytes memory data) external;

    function setOperator(address operator) external;

    function setStrategistFee(uint256 fee) external;
}
