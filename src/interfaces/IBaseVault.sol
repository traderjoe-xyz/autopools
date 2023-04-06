// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ILBPair} from "joe-v2/interfaces/ILBPair.sol";

import {IStrategy} from "./IStrategy.sol";
import {IVaultFactory} from "./IVaultFactory.sol";

/**
 * @title Base Vault Interface
 * @author Trader Joe
 * @notice Interface used to interact with Liquidity Book Vaults
 */
interface IBaseVault is IERC20Upgradeable {
    error BaseVault__AlreadyWhitelisted(address user);
    error BaseVault__BurnMinShares();
    error BaseVault__DepositsPaused();
    error BaseVault__InvalidNativeAmount();
    error BaseVault__InvalidRecipient();
    error BaseVault__InvalidShares();
    error BaseVault__InvalidStrategy();
    error BaseVault__InvalidToken();
    error BaseVault__NoNativeToken();
    error BaseVault__NoQueuedWithdrawal();
    error BaseVault__MaxSharesExceeded();
    error BaseVault__NativeTransferFailed();
    error BaseVault__NotInEmergencyMode();
    error BaseVault__NotWhitelisted(address user);
    error BaseVault__OnlyFactory();
    error BaseVault__OnlyWNative();
    error BaseVault__OnlyStrategy();
    error BaseVault__SameStrategy();
    error BaseVault__SameWhitelistState();
    error BaseVault__ZeroAmount();
    error BaseVault__ZeroShares();
    error BaseVault__InvalidRound();

    struct QueuedWithdrawal {
        mapping(address => uint256) userWithdrawals;
        uint256 totalQueuedShares;
        uint128 totalAmountX;
        uint128 totalAmountY;
    }

    event Deposited(address indexed user, uint256 amountX, uint256 amountY, uint256 shares);

    event WithdrawalQueued(address indexed sender, address indexed user, uint256 indexed round, uint256 shares);

    event WithdrawalCancelled(address indexed sender, address indexed recipient, uint256 indexed round, uint256 shares);

    event WithdrawalRedeemed(
        address indexed sender,
        address indexed recipient,
        uint256 indexed round,
        uint256 shares,
        uint256 amountX,
        uint256 amountY
    );

    event WithdrawalExecuted(uint256 indexed round, uint256 totalQueuedQhares, uint256 amountX, uint256 amountY);

    event StrategySet(IStrategy strategy);

    event WhitelistStateChanged(bool state);

    event WhitelistAdded(address[] addresses);

    event WhitelistRemoved(address[] addresses);

    event DepositsPaused();

    event DepositsResumed();

    event EmergencyMode();

    event EmergencyWithdrawal(address indexed sender, uint256 shares, uint256 amountX, uint256 amountY);

    function getFactory() external view returns (IVaultFactory);

    function getPair() external view returns (ILBPair);

    function getTokenX() external view returns (IERC20Upgradeable);

    function getTokenY() external view returns (IERC20Upgradeable);

    function getStrategy() external view returns (IStrategy);

    function getAumAnnualFee() external view returns (uint256);

    function getRange() external view returns (uint24 low, uint24 upper);

    function getOperators() external view returns (address defaultOperator, address operator);

    function getBalances() external view returns (uint256 amountX, uint256 amountY);

    function previewShares(uint256 amountX, uint256 amountY)
        external
        view
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY);

    function previewAmounts(uint256 shares) external view returns (uint256 amountX, uint256 amountY);

    function isDepositsPaused() external view returns (bool);

    function isWhitelistedOnly() external view returns (bool);

    function isWhitelisted(address user) external view returns (bool);

    function getCurrentRound() external view returns (uint256 round);

    function getQueuedWithdrawal(uint256 round, address user) external view returns (uint256 shares);

    function getTotalQueuedWithdrawal(uint256 round) external view returns (uint256 totalQueuedShares);

    function getCurrentTotalQueuedWithdrawal() external view returns (uint256 totalQueuedShares);

    function getRedeemableAmounts(uint256 round, address user)
        external
        view
        returns (uint256 amountX, uint256 amountY);

    function deposit(uint256 amountX, uint256 amountY)
        external
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY);

    function depositNative(uint256 amountX, uint256 amountY)
        external
        payable
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY);

    function queueWithdrawal(uint256 shares, address recipient) external returns (uint256 round);

    function cancelQueuedWithdrawal(uint256 shares, address recipient) external returns (uint256 round);

    function redeemQueuedWithdrawal(uint256 round, address recipient)
        external
        returns (uint256 amountX, uint256 amountY);

    function redeemQueuedWithdrawalNative(uint256 round, address recipient)
        external
        returns (uint256 amountX, uint256 amountY);

    function emergencyWithdraw() external;

    function executeQueuedWithdrawals() external;

    function initialize(string memory name, string memory symbol) external;

    function setStrategy(IStrategy newStrategy) external;

    function setWhitelistState(bool state) external;

    function addToWhitelist(address[] calldata addresses) external;

    function removeFromWhitelist(address[] calldata addresses) external;

    function pauseDeposits() external;

    function resumeDeposits() external;

    function setEmergencyMode() external;

    function recoverERC20(IERC20Upgradeable token, address recipient, uint256 amount) external;
}
