// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ILBPair} from "joe-v2/interfaces/ILBPair.sol";

interface IStrategy {
    error Strategy__OnlyFactory();
    error Strategy__Unhautorized();
    error Strategy__InvalidDistribution();
    error Strategy__SwapFailed();
    error Strategy__InvalidData();
    error Strategy__InvalidSrcToken();
    error Strategy__InvalidDstToken();
    error Strategy__InvalidReceiver();
    error Strategy__InvalidPrice();
    error Strategy__InvalidRange();
    error Strategy__InvalidRemovedRange();
    error Strategy__InvalidAddedRange();

    event OperatorSet(address operator);

    function getVault() external pure returns (address);

    function getPair() external pure returns (ILBPair);

    function getTokenX() external pure returns (IERC20Upgradeable);

    function getTokenY() external pure returns (IERC20Upgradeable);

    function getRange() external view returns (uint24 low, uint24 upper);

    function getStrategistFee() external view returns (uint256 fee);

    function getOperator() external view returns (address);

    function getBalances() external view returns (uint256 amountX, uint256 amountY);

    function getPendingFees() external view returns (uint256 amountX, uint256 amountY);

    function withdraw(uint256 shares, uint256 totalSupply, address to)
        external
        returns (uint256 amountX, uint256 amountY);

    function expandRange(
        uint24 addedLow,
        uint24 addedUpper,
        uint256[] calldata distributionX,
        uint256[] calldata distributionY,
        uint256 amountX,
        uint256 amountY
    ) external;

    function shrinkRange(uint24 removedLow, uint24 removedUpper, uint256 percentageToRemove) external;

    function collectFees() external;

    function swap(bytes memory data) external;

    function setOperator(address operator) external;
}
