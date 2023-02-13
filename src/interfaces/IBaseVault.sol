// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ILBPair} from "joe-v2/interfaces/ILBPair.sol";

import {IStrategy} from "./IStrategy.sol";
import {IVaultFactory} from "./IVaultFactory.sol";

interface IBaseVault is IERC20Upgradeable {
    error BaseVault__ZeroAmount();
    error BaseVault__OnlyFactory();
    error BaseVault__InvalidStrategy();
    error BaseVault__InvalidToken();
    error BaseVault__SameStrategy();
    error BaseVault__InvalidShares();
    error BaseVault__ZeroShares();
    error BaseVault__BurnMinShares();
    error BaseVault__NoNativeToken();
    error BaseVault__InvalidNativeAmount();
    error BaseVault__NativeTransferFailed();

    event Deposited(address indexed user, uint256 amountX, uint256 amountY, uint256 shares);

    event Withdrawn(address indexed user, uint256 amountX, uint256 amountY, uint256 shares);

    event StrategySet(IStrategy strategy);

    event DepositFeeSet(uint256 fee);

    event WithdrawalFeeSet(uint256 fee);

    function getFactory() external view returns (IVaultFactory);

    function getPair() external view returns (ILBPair);

    function getTokenX() external view returns (IERC20Upgradeable);

    function getTokenY() external view returns (IERC20Upgradeable);

    function getStrategy() external view returns (IStrategy);

    function getStrategistFee() external view returns (uint256);

    function getRange() external view returns (uint24 low, uint24 upper);

    function getOperators() external view returns (address defaultOperator, address operator);

    function getBalances() external view returns (uint256 amountX, uint256 amountY);

    function getPendingFees() external view returns (uint256 amountX, uint256 amountY);

    function previewShares(uint256 amountX, uint256 amountY)
        external
        view
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY);

    function previewAmounts(uint256 shares) external view returns (uint256 amountX, uint256 amountY);

    function deposit(uint256 amountX, uint256 amountY)
        external
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY);

    function depositNative(uint256 amountX, uint256 amountY)
        external
        payable
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY);

    function withdraw(uint256 shares) external returns (uint256 amountX, uint256 amountY);

    function initialize(string memory name, string memory symbol) external;

    function setStrategy(IStrategy newStrategy) external;

    function pauseVault() external;

    function recoverERC20(IERC20Upgradeable token, address recipient, uint256 amount) external;
}
