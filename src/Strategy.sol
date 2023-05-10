// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {SafeCast} from "joe-v2/libraries/math/SafeCast.sol";
import {PriceHelper} from "joe-v2/libraries/PriceHelper.sol";
import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ILBPair} from "joe-v2/interfaces/ILBPair.sol";
import {ILBToken} from "joe-v2/interfaces/ILBToken.sol";
import {LiquidityAmounts} from "joe-v2-periphery/periphery/LiquidityAmounts.sol";
import {Uint256x256Math} from "joe-v2/libraries/math/Uint256x256Math.sol";
import {LiquidityConfigurations} from "joe-v2/libraries/math/LiquidityConfigurations.sol";
import {Clone} from "joe-v2/libraries/Clone.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {IStrategy} from "./interfaces/IStrategy.sol";
import {IBaseVault} from "./interfaces/IBaseVault.sol";
import {IVaultFactory} from "./interfaces/IVaultFactory.sol";
import {Math} from "./libraries/Math.sol";
import {IOneInchRouter} from "./interfaces/IOneInchRouter.sol";

/**
 * @title Liquidity Book Simple SimpleStrategy contract
 * @author Trader Joe
 * @notice This contract is used to interact with the Liquidity Book Pair contract.
 * It is used to manage the liquidity of the vault.
 * The immutable data should be encoded as follow:
 * - 0x00: 20 bytes: The address of the Vault.
 * - 0x14: 20 bytes: The address of the LB pair.
 * - 0x28: 20 bytes: The address of the token X.
 * - 0x3C: 20 bytes: The address of the token Y.
 * - 0x50: 2 bytes: The bin step of the lb pair.
 */
contract Strategy is Clone, ReentrancyGuardUpgradeable, IStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LiquidityAmounts for address;
    using Math for uint256;
    using PriceHelper for uint24;
    using SafeCast for uint256;
    using Uint256x256Math for uint256;

    IOneInchRouter private constant _ONE_INCH_ROUTER = IOneInchRouter(0x1111111254EEB25477B68fb85Ed929f73A960582);

    uint256 private constant _PRECISION = 1e18;
    uint256 private constant _BASIS_POINTS = 1e4;

    uint256 private constant _MAX_RANGE = 51;
    uint256 private constant _MAX_AUM_ANNUAL_FEE = 0.25e4; // 25%

    uint256 private constant _SCALED_YEAR = 365 days * _BASIS_POINTS;
    uint256 private constant _SCALED_YEAR_SUB_ONE = _SCALED_YEAR - 1;

    uint8 private constant _OFFSET = 128;
    uint256 private constant _PACKED_DISTRIBS_SIZE = 16;

    IVaultFactory private immutable _factory;

    uint24 private _lowerRange;
    uint24 private _upperRange;
    uint16 private _aumAnnualFee;
    uint64 private _lastRebalance;
    uint16 private _pendingAumAnnualFee;
    bool private _pendingAumAnnualFeeSet;

    address private _operator;

    /**
     * @notice Modifier to check if the caller is the factory.
     */
    modifier onlyFactory() {
        if (msg.sender != address(_factory)) revert Strategy__OnlyFactory();
        _;
    }

    /**
     * @notice Modifier to check if the caller is the vault.
     */
    modifier onlyVault() {
        if (msg.sender != _vault()) revert Strategy__OnlyVault();
        _;
    }

    /**
     * @notice Modifier to check if the caller is the operator or the default operator.
     */
    modifier onlyOperators() {
        if (msg.sender != _operator && msg.sender != _factory.getDefaultOperator()) revert Strategy__OnlyOperators();
        _;
    }

    /**
     * @dev Constructor of the contract.
     * @param factory The address of the factory.
     */
    constructor(IVaultFactory factory) {
        _disableInitializers();

        _factory = factory;
    }

    /**
     * @notice Initialize the contract.
     */
    function initialize() external initializer {
        __ReentrancyGuard_init();
    }

    /**
     * @notice Returns the address of the factory.
     * @return The address of the factory.
     */
    function getFactory() external view override returns (IVaultFactory) {
        return _factory;
    }

    /**
     * @notice Returns the address of the vault.
     * @return The address of the vault.
     */
    function getVault() external pure override returns (address) {
        return _vault();
    }

    /**
     * @notice Returns the address of the pair.
     * @return The address of the pair.
     */
    function getPair() external pure override returns (ILBPair) {
        return _pair();
    }

    /**
     * @notice Returns the address of the token X.
     * @return The address of the token X.
     */
    function getTokenX() external pure override returns (IERC20Upgradeable) {
        return _tokenX();
    }

    /**
     * @notice Returns the address of the token Y.
     * @return The address of the token Y.
     */
    function getTokenY() external pure override returns (IERC20Upgradeable) {
        return _tokenY();
    }

    /**
     * @notice Returns the range of the strategy.
     * @return lower The lower bound of the range.
     * @return upper The upper bound of the range.
     */
    function getRange() external view override returns (uint24 lower, uint24 upper) {
        return (_lowerRange, _upperRange);
    }

    /**
     * @notice Returns the operator of the strategy.
     * @return operator The operator of the strategy.
     */
    function getOperator() external view override returns (address operator) {
        return _operator;
    }

    /**
     * @notice Returns the balances of the strategy.
     * @return amountX The amount of token X.
     * @return amountY The amount of token Y.
     */
    function getBalances() external view override returns (uint256 amountX, uint256 amountY) {
        return _getBalances();
    }

    /**
     * @notice Returns the idle balances of the strategy.
     * @return amountX The idle amount of token X.
     * @return amountY The idle amount of token Y.
     */
    function getIdleBalances() external view override returns (uint256 amountX, uint256 amountY) {
        amountX = _tokenX().balanceOf(address(this));
        amountY = _tokenY().balanceOf(address(this));
    }

    /**
     * @notice Returns the assets under management annual fee.
     * @return aumAnnualFee The assets under management annual fee.
     */
    function getAumAnnualFee() external view override returns (uint256 aumAnnualFee) {
        return _aumAnnualFee;
    }

    /**
     * @notice Returns the last rebalance timestamp.
     * @return lastRebalance The last rebalance timestamp.
     */
    function getLastRebalance() external view override returns (uint256 lastRebalance) {
        return _lastRebalance;
    }

    /**
     * @notice Returns the pending assets under management annual fee.
     * @return isSet True if the pending assets under management annual fee is set.
     * @return pendingAumAnnualFee The pending assets under management annual fee.
     * If the pending assets under management annual fee is not set, this value is zero.
     */
    function getPendingAumAnnualFee() external view override returns (bool isSet, uint256 pendingAumAnnualFee) {
        return (_pendingAumAnnualFeeSet, _pendingAumAnnualFee);
    }

    /**
     * @notice Withdraws all the tokens from the LB pool and sends the entire balance of the strategy to the vault.
     * The queued withdrawals will be executed.
     * This function will only be called during the migration of strategies and during emergency withdrawals.
     * @dev Only the vault can call this function.
     */
    function withdrawAll() external override onlyVault {
        address vault = _vault();

        // Withdraw all the tokens from the LB pool and return the amounts and the queued withdrawals.
        (uint256 amountX, uint256 amountY, uint256 queuedShares, uint256 queuedAmountX, uint256 queuedAmountY) =
            _withdraw(_lowerRange, _upperRange, IBaseVault(vault).totalSupply());

        // Execute the queued withdrawals and send the tokens to the vault.
        _transferAndExecuteQueuedAmounts(queuedShares, queuedAmountX, queuedAmountY);

        // Send the tokens to the vault.
        _tokenX().safeTransfer(vault, amountX);
        _tokenY().safeTransfer(vault, amountY);
    }

    /**
     * @notice Rebalances the strategy by withdrawing the entire position and depositing the new position.
     * It will deposit the tokens following the amounts valued in Y.
     * @dev Only the operator can call this function.
     * @param newLower The lower bound of the new range.
     * @param newUpper The upper bound of the new range.
     * @param desiredActiveId The desired active id.
     * @param slippageActiveId The slippage active id.
     * @param distributions The packed distributions. Each bytes16 of the distributions bytes is
     * (distributionX, distributionY) from the `newLower`to the `newUpper` range.
     * @param amountX The amount of token X to deposit.
     * @param amountY The amount of token Y to deposit.
     */
    function rebalance(
        uint24 newLower,
        uint24 newUpper,
        uint24 desiredActiveId,
        uint24 slippageActiveId,
        uint256 amountX,
        uint256 amountY,
        bytes calldata distributions
    ) external override onlyOperators {
        {
            // Withdraw all the tokens from the LB pool and return the amounts and the queued withdrawals.
            // It will also charge the AUM annual fee based on the last time a rebalance was executed.
            (uint256 queuedShares, uint256 queuedAmountX, uint256 queuedAmountY) = _withdrawAndApplyAumAnnualFee();

            // Execute the queued withdrawals and send the tokens to the vault.
            _transferAndExecuteQueuedAmounts(queuedShares, queuedAmountX, queuedAmountY);
        }

        // Check if the operator wants to deposit tokens.
        if (desiredActiveId > 0 || slippageActiveId > 0) {
            // Adjust the range and get the active id, in case the active id changed.
            uint24 activeId;
            (activeId, newLower, newUpper) = _adjustRange(newLower, newUpper, desiredActiveId, slippageActiveId);

            // Get the distributions and the amounts to deposit
            bytes32[] memory liquidityConfigs = _getLiquidityConfigs(newLower, newUpper, distributions);

            // Deposit the tokens to the LB pool.
            _depositToLB(newLower, newUpper, liquidityConfigs, amountX, amountY);
        }
    }

    /**
     * @notice Swaps tokens using 1inch.
     * @dev Only the operator can call this function.
     * @param executor The address that will execute the swap.
     * @param desc The swap description.
     * @param data The data to be passed to the 1inch router.
     */
    function swap(address executor, IOneInchRouter.SwapDescription calldata desc, bytes calldata data)
        external
        override
        onlyOperators
    {
        IERC20Upgradeable tokenX = _tokenX();
        IERC20Upgradeable tokenY = _tokenY();

        if (
            (desc.srcToken != tokenX || desc.dstToken != tokenY) && (desc.srcToken != tokenY || desc.dstToken != tokenX)
        ) {
            revert Strategy__InvalidToken();
        }

        if (desc.dstReceiver != address(this)) revert Strategy__InvalidReceiver();
        if (desc.amount == 0 || desc.minReturnAmount == 0) revert Strategy__InvalidAmount();

        desc.srcToken.safeApprove(address(_ONE_INCH_ROUTER), desc.amount);

        _ONE_INCH_ROUTER.swap(executor, desc, "", data);

        if (desc.srcToken.allowance(address(this), address(_ONE_INCH_ROUTER)) != 0) {
            desc.srcToken.safeApprove(address(_ONE_INCH_ROUTER), 0);
        }
    }

    /**
     * @notice Sets the operator.
     * @dev Only the factory can call this function.
     * @param operator The address of the operator.
     */
    function setOperator(address operator) external override onlyFactory {
        _operator = operator;

        emit OperatorSet(operator);
    }

    /**
     * @notice Sets the pending assets under management annual fee.
     * @dev Only the factory can call this function.
     * @param pendingAumAnnualFee The assets under management annual fee.
     */
    function setPendingAumAnnualFee(uint16 pendingAumAnnualFee) external override onlyFactory {
        if (pendingAumAnnualFee > _MAX_AUM_ANNUAL_FEE) revert Strategy__InvalidFee();

        _pendingAumAnnualFeeSet = true;
        _pendingAumAnnualFee = pendingAumAnnualFee;

        emit PendingAumAnnualFeeSet(pendingAumAnnualFee);
    }

    /**
     * @notice Resets the pending assets under management annual fee.
     * @dev Only the factory can call this function.
     */
    function resetPendingAumAnnualFee() external override onlyFactory {
        _pendingAumAnnualFeeSet = false;
        _pendingAumAnnualFee = 0;

        emit PendingAumAnnualFeeReset();
    }

    /**
     * @dev Returns the address of the vault.
     * @return vault The address of the vault.
     */
    function _vault() internal pure returns (address vault) {
        vault = _getArgAddress(0);
    }

    /**
     * @dev Returns the address of the pair.
     * @return pair The address of the pair.
     */
    function _pair() internal pure returns (ILBPair pair) {
        pair = ILBPair(_getArgAddress(20));
    }

    /**
     * @dev Returns the address of the token X.
     * @return tokenX The address of the token X.
     */
    function _tokenX() internal pure returns (IERC20Upgradeable tokenX) {
        tokenX = IERC20Upgradeable(_getArgAddress(40));
    }

    /**
     * @dev Returns the address of the token Y.
     * @return tokenY The address of the token Y.
     */
    function _tokenY() internal pure returns (IERC20Upgradeable tokenY) {
        tokenY = IERC20Upgradeable(_getArgAddress(60));
    }

    /**
     * @dev Returns the ids of the tokens in the range.
     * @param lower The lower end of the range.
     * @param upper The upper end of the range.
     * @return ids The ids of the tokens in the range.
     */
    function _getIds(uint24 lower, uint24 upper) internal pure returns (uint256[] memory ids) {
        // Get the delta of the range, we add 1 because the upper bound is inclusive.
        uint256 delta = upper - lower + 1;

        // Get the ids from lower to upper (inclusive).
        ids = new uint256[](delta);
        for (uint256 i; i < delta;) {
            ids[i] = lower + i;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Returns the balances of the contract, including those deposited in the LB pool.
     * @return amountX The balance of token X.
     * @return amountY The balance of token Y.
     */
    function _getBalances() internal view returns (uint256 amountX, uint256 amountY) {
        // Get the balances of the tokens in the contract.
        amountX = _tokenX().balanceOf(address(this));
        amountY = _tokenY().balanceOf(address(this));

        // Get the range of the tokens in the pool.
        (uint24 lower, uint24 upper) = (_lowerRange, _upperRange);

        // If the range is not empty, get the balances of the tokens in the range.
        if (upper != 0) {
            uint256[] memory ids = _getIds(lower, upper);

            (uint256 depositedX, uint256 depositedY) = address(this).getAmountsOf(ids, address(_pair()));

            amountX += depositedX;
            amountY += depositedY;
        }
    }

    /**
     * @dev Returns the active id of the pair.
     * @return activeId The active id of the pair.
     */
    function _getActiveId() internal view returns (uint24 activeId) {
        activeId = _pair().getActiveId();
    }

    /**
     * @dev Adjusts the range if the active id is different from the desired active id.
     * Will revert if the active id is not within the desired active id and the slippage.
     * @param newLower The lower end of the new range.
     * @param newUpper The upper end of the new range.
     * @param desiredActiveId The desired active id.
     * @param slippageActiveId The allowed slippage of the active id.
     */
    function _adjustRange(uint24 newLower, uint24 newUpper, uint24 desiredActiveId, uint24 slippageActiveId)
        internal
        view
        returns (uint24 activeId, uint24, uint24)
    {
        activeId = _getActiveId();

        // If the active id is different from the desired active id, adjust the range.
        if (desiredActiveId != activeId) {
            uint24 delta;

            if (desiredActiveId > activeId) {
                // If the desired active id is greater than the active id, we need to decrease the range.
                unchecked {
                    delta = desiredActiveId - activeId;

                    newLower = newLower > delta ? newLower - delta : 0;
                    newUpper = newUpper > delta ? newUpper - delta : 0;
                }
            } else {
                // If the desired active id is lower than the active id, we need to increase the range.
                unchecked {
                    delta = activeId - desiredActiveId;

                    newLower = newLower > type(uint24).max - delta ? type(uint24).max : newLower + delta;
                    newUpper = newUpper > type(uint24).max - delta ? type(uint24).max : newUpper + delta;
                }
            }

            // If the delta is greater than the slippage, revert.
            if (delta > slippageActiveId) revert Strategy__ActiveIdSlippage();
        }

        return (activeId, newLower, newUpper);
    }

    /**
     * @dev Returns the liquidity configurations for the given range.
     * @param idLower The lower end of the range.
     * @param idUpper The upper end of the range.
     * @param distributions The packed distributions. Each bytes16 of the distributions bytes is
     * (distributionX, distributionY) from the `newLower`to the `newUpper` range. can be calculated as:
     * distributions = abi.encodePacked(uint64(distribX0), uint64(distribY0), uint64(distribX1), uint64(distribY1), ...)
     * @return liquidityConfigs The liquidity configurations for the given range.
     */
    function _getLiquidityConfigs(uint24 idLower, uint24 idUpper, bytes calldata distributions)
        internal
        pure
        returns (bytes32[] memory liquidityConfigs)
    {
        if (idUpper == 0 || idLower > idUpper) revert Strategy__InvalidRange();
        if (distributions.length != (idUpper - idLower + 1) * _PACKED_DISTRIBS_SIZE) revert Strategy__InvalidLength();

        uint256 length = distributions.length / _PACKED_DISTRIBS_SIZE;

        liquidityConfigs = new bytes32[](length);

        uint256 index;
        for (uint256 i; i < length; ++i) {
            uint24 id = idLower + uint24(i);

            uint128 distribs = uint128(bytes16(distributions[index:index += _PACKED_DISTRIBS_SIZE]));

            liquidityConfigs[i] = LiquidityConfigurations.encodeParams(uint64(distribs >> 64), uint64(distribs), id);
        }
    }

    /**
     * @dev Sets the range only if it is not already set. Will revert if the range is already set.
     * @param newLower The lower end of the new range.
     * @param newUpper The upper end of the new range.
     */
    function _setRange(uint24 newLower, uint24 newUpper) internal {
        if (newUpper == 0 || newLower > newUpper) revert Strategy__InvalidRange();
        if (newUpper - newLower + 1 > _MAX_RANGE) revert Strategy__RangeTooWide();

        uint24 previousUpper = _upperRange;

        // If there is a current range, it reverts
        if (previousUpper != 0) revert Strategy__RangeAlreadySet();

        // If the range is not set, it will set the range to the new range.
        _lowerRange = newLower;
        _upperRange = newUpper;

        emit RangeSet(newLower, newUpper);
    }

    /**
     * @dev Resets the range.
     */
    function _resetRange() internal {
        _lowerRange = 0;
        _upperRange = 0;

        emit RangeSet(0, 0);
    }

    /**
     * @dev Deposits tokens into the pair.
     * @param lower The lower end of the range.
     * @param upper The upper end of the range.
     * @param liquidityConfigs The liquidity configurations, encoded as bytes32.
     * @param amountX The amount of token X to deposit.
     * @param amountY The amount of token Y to deposit.
     */
    function _depositToLB(
        uint24 lower,
        uint24 upper,
        bytes32[] memory liquidityConfigs,
        uint256 amountX,
        uint256 amountY
    ) internal {
        // Set the range, will check if the range is valid.
        _setRange(lower, upper);

        if (amountX == 0 && amountY == 0) revert Strategy__ZeroAmounts();

        // Get the pair address and transfer the tokens to the pair.
        address pair = address(_pair());

        if (amountX > 0) _tokenX().safeTransfer(pair, amountX);
        if (amountY > 0) _tokenY().safeTransfer(pair, amountY);

        // Mint the liquidity tokens.
        ILBPair(pair).mint(address(this), liquidityConfigs, address(this));
    }

    /**
     * @dev Withdraws tokens from the pair and applies the AUM annual fee. This function will also reset the range.
     * Will never charge for more than a day of AUM fees, even if the strategy has not been rebalanced for a longer period.
     * @return queuedShares The amount of shares that were queued for withdrawal.
     * @return queuedAmountX The amount of token X that was queued for withdrawal.
     * @return queuedAmountY The amount of token Y that was queued for withdrawal.
     */
    function _withdrawAndApplyAumAnnualFee()
        internal
        returns (uint256 queuedShares, uint256 queuedAmountX, uint256 queuedAmountY)
    {
        // Get the range and reset it.
        (uint24 lowerRange, uint24 upperRange) = (_lowerRange, _upperRange);
        if (upperRange > 0) _resetRange();

        // Get the total balance of the strategy and the queued shares and amounts.
        uint256 totalBalanceX;
        uint256 totalBalanceY;

        (totalBalanceX, totalBalanceY, queuedShares, queuedAmountX, queuedAmountY) =
            _withdraw(lowerRange, upperRange, IBaseVault(_vault()).totalSupply());

        // Get the total balance of the strategy.
        totalBalanceX += queuedAmountX;
        totalBalanceY += queuedAmountY;

        // Ge the last rebalance timestamp and update it.
        uint256 lastRebalance = _lastRebalance;
        _lastRebalance = block.timestamp.safe64();

        // If the total balance is 0, early return to not charge the AUM annual fee nor update it.
        if (totalBalanceX == 0 && totalBalanceY == 0) return (queuedShares, queuedAmountX, queuedAmountY);

        // Apply the AUM annual fee
        if (lastRebalance < block.timestamp) {
            uint256 annualFee = _aumAnnualFee;

            if (annualFee > 0) {
                address feeRecipient = _factory.getFeeRecipient();

                // Get the duration of the last rebalance and cap it to 1 day.
                uint256 duration = block.timestamp - lastRebalance;
                duration = duration > 1 days ? 1 days : duration;

                // Round up the fees and transfer them to the fee recipient.
                uint256 feeX = (totalBalanceX * annualFee * duration + _SCALED_YEAR_SUB_ONE) / _SCALED_YEAR;
                uint256 feeY = (totalBalanceY * annualFee * duration + _SCALED_YEAR_SUB_ONE) / _SCALED_YEAR;

                if (feeX > 0) {
                    // Adjusts the queued amount of token X to account for the fee.
                    queuedAmountX =
                        queuedAmountX == 0 ? 0 : queuedAmountX - feeX.mulDivRoundUp(queuedAmountX, totalBalanceX);

                    _tokenX().safeTransfer(feeRecipient, feeX);
                }
                if (feeY > 0) {
                    // Adjusts the queued amount of token Y to account for the fee.
                    queuedAmountY =
                        queuedAmountY == 0 ? 0 : queuedAmountY - feeY.mulDivRoundUp(queuedAmountY, totalBalanceY);

                    _tokenY().safeTransfer(feeRecipient, feeY);
                }

                emit AumFeeCollected(msg.sender, totalBalanceX, totalBalanceY, feeX, feeY);
            }
        }

        // Update the pending AUM annual fee if needed.
        if (_pendingAumAnnualFeeSet) {
            _pendingAumAnnualFeeSet = false;

            uint16 pendingAumAnnualFee = _pendingAumAnnualFee;

            _pendingAumAnnualFee = 0;
            _aumAnnualFee = pendingAumAnnualFee;

            emit AumAnnualFeeSet(pendingAumAnnualFee);
        }
    }

    /**
     * @dev Withdraws tokens from the pair also withdraw the queued withdraws.
     * @param removedLower The lower end of the range to remove.
     * @param removedUpper The upper end of the range to remove.
     * @param totalShares The total amount of shares.
     * @return amountX The amount of token X withdrawn.
     * @return amountY The amount of token Y withdrawn.
     * @return queuedShares The amount of shares withdrawn from the queued withdraws.
     * @return queuedAmountX The amount of token X withdrawn from the queued withdraws.
     * @return queuedAmountY The amount of token Y withdrawn from the queued withdraws.
     */
    function _withdraw(uint24 removedLower, uint24 removedUpper, uint256 totalShares)
        internal
        returns (uint256 amountX, uint256 amountY, uint256 queuedShares, uint256 queuedAmountX, uint256 queuedAmountY)
    {
        // Get the amount of shares queued for withdrawal.
        queuedShares = IBaseVault(_vault()).getCurrentTotalQueuedWithdrawal();

        // Withdraw from the Liquidity Book Pair and get the amounts of tokens in the strategy.
        (uint256 balanceX, uint256 balanceY) = _withdrawFromLB(removedLower, removedUpper);

        // Get the amount of tokens to withdraw from the queued withdraws.
        (queuedAmountX, queuedAmountY) = totalShares == 0 || queuedShares == 0
            ? (0, 0)
            : (queuedShares.mulDivRoundDown(balanceX, totalShares), queuedShares.mulDivRoundDown(balanceY, totalShares));

        // Get the amount that were not queued for withdrawal.
        amountX = balanceX - queuedAmountX;
        amountY = balanceY - queuedAmountY;
    }

    /**
     * @dev Withdraws tokens from the Liquidity Book Pair.
     * @param removedLower The lower end of the range to remove.
     * @param removedUpper The upper end of the range to remove.
     * @return balanceX The amount of token X in the strategy.
     * @return balanceY The amount of token Y in the strategy.
     */
    function _withdrawFromLB(uint24 removedLower, uint24 removedUpper)
        internal
        returns (uint256 balanceX, uint256 balanceY)
    {
        uint256 length;

        // Get the pair address and the delta between the upper and lower range.
        address pair = address(_pair());
        uint256 delta = removedUpper - removedLower + 1;

        uint256[] memory ids = new uint256[](delta);
        uint256[] memory amounts = new uint256[](delta);

        if (removedUpper > 0) {
            // Get the ids and amounts of the tokens to withdraw.
            for (uint256 i; i < delta;) {
                uint256 id = removedLower + i;
                uint256 amount = ILBToken(pair).balanceOf(address(this), id);

                if (amount != 0) {
                    ids[length] = id;
                    amounts[length] = amount;

                    unchecked {
                        ++length;
                    }
                }

                unchecked {
                    ++i;
                }
            }
        }

        // If the range is not empty, burn the tokens from the pair.
        if (length > 0) {
            // If the length is different than the delta, update the arrays, this allows to avoid the zero shares error.
            if (length != delta) {
                assembly {
                    mstore(ids, length)
                    mstore(amounts, length)
                }
            }

            // Burn the tokens from the pair.
            ILBPair(pair).burn(address(this), address(this), ids, amounts);
        }

        // Get the amount of tokens in the strategy.
        balanceX = IERC20Upgradeable(_tokenX()).balanceOf(address(this));
        balanceY = IERC20Upgradeable(_tokenY()).balanceOf(address(this));
    }

    /**
     * @dev Transfers the queued withdraws to the vault and calls the executeQueuedWithdrawals function.
     * @param queuedShares The amount of shares withdrawn from the queued withdraws.
     * @param queuedAmountX The amount of token X withdrawn from the queued withdraws.
     * @param queuedAmountY The amount of token Y withdrawn from the queued withdraws.
     */
    function _transferAndExecuteQueuedAmounts(uint256 queuedShares, uint256 queuedAmountX, uint256 queuedAmountY)
        private
    {
        if (queuedShares > 0) {
            address vault = _vault();

            // Transfer the tokens to the vault and execute the queued withdraws.
            if (queuedAmountX > 0) _tokenX().safeTransfer(vault, queuedAmountX);
            if (queuedAmountY > 0) _tokenY().safeTransfer(vault, queuedAmountY);

            IBaseVault(vault).executeQueuedWithdrawals();
        }
    }
}
