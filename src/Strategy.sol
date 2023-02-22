// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {SafeCast} from "joe-v2/libraries/SafeCast.sol";
import {BinHelper} from "joe-v2/libraries/BinHelper.sol";
import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ILBPair} from "joe-v2/interfaces/ILBPair.sol";
import {ILBToken} from "joe-v2/interfaces/ILBToken.sol";
import {ILBToken} from "joe-v2/interfaces/ILBToken.sol";
import {LiquidityAmounts} from "joe-v2-periphery/periphery/LiquidityAmounts.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {BinHelper} from "joe-v2/libraries/BinHelper.sol";
import {SafeERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {IStrategy} from "./interfaces/IStrategy.sol";
import {IVaultFactory} from "./interfaces/IVaultFactory.sol";
import {CloneExtension} from "./libraries/CloneExtension.sol";
import {Encoded} from "./libraries/Encoded.sol";
import {Math} from "./libraries/Math.sol";
import {Range} from "./libraries/Range.sol";
import {Distribution} from "./libraries/Distribution.sol";

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
contract Strategy is CloneExtension, ReentrancyGuardUpgradeable, IStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LiquidityAmounts for address;
    using Encoded for bytes32;
    using Math for uint256;
    using Range for uint24;
    using Distribution for uint256[];
    using BinHelper for uint256;
    using SafeCast for uint256;

    address private constant _ONE_INCH_ROUTER = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    uint256 private constant _PRECISION = 1e18;
    uint256 private constant _BASIS_POINTS = 1e4;
    uint256 private constant _MAX_AUM_ANNUAL_FEE = 0.25e4; // 25%
    uint256 private constant _SCALED_YEAR = 365 days * _BASIS_POINTS;
    uint256 private constant _SCALED_YEAR_SUB_ONE = _SCALED_YEAR - 1;

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

        IERC20Upgradeable(_tokenX()).approve(_ONE_INCH_ROUTER, type(uint256).max);
        IERC20Upgradeable(_tokenY()).approve(_ONE_INCH_ROUTER, type(uint256).max);
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
     * @notice Returns the pending fees of the strategy.
     * @return amountX The amount of token X.
     * @return amountY The amount of token Y.
     */
    function getPendingFees() external view override returns (uint256 amountX, uint256 amountY) {
        (uint24 lower, uint24 upper) = (_lowerRange, _upperRange);

        return upper == 0 ? (0, 0) : _getPendingFees(_getIds(lower, upper));
    }

    /**
     * @notice Returns the assets under management annual fee.
     * @return aumAnnualFee The assets under management annual fee.
     */
    function getAumAnnualFee() external view override returns (uint256 aumAnnualFee) {
        return _aumAnnualFee;
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
     * @notice Collect the fees from the LB pool.
     */
    function collectFees() external override {
        (uint24 lower, uint24 upper) = (_lowerRange, _upperRange);

        if (upper > 0) _collectFees(_getIds(lower, upper));
    }

    /**
     * @notice Withdraws tokens from the strategy and the LB pool.
     * @dev Only the vault can call this function.
     * @param shares The amount of shares to withdraw.
     * @param totalShares The total amount of shares.
     * @param to The address to send the tokens to.
     */
    function withdraw(uint256 shares, uint256 totalShares, address to)
        external
        override
        onlyVault
        returns (uint256 amountX, uint256 amountY)
    {
        (amountX, amountY) = _withdraw(_lowerRange, _upperRange, shares, totalShares);

        _tokenX().safeTransfer(to, amountX);
        _tokenY().safeTransfer(to, amountY);
    }

    /**
     * @notice Rebalances the strategy by depositing and withdrawing tokens from the LB pool.
     * It will deposit the tokens following the amounts valued in Y.
     * @dev Only the operator can call this function.
     * @param newLower The lower bound of the new range.
     * @param newUpper The upper bound of the new range.
     * @param desiredActiveId The desired active id.
     * @param slippageActiveId The slippage active id.
     * @param amountsInY The amounts of tokens, valued in Y.
     * @param maxPercentageToAddX The maximum percentage of token X to add.
     * @param maxPercentageToAddY The maximum percentage of token Y to add.
     */
    function rebalanceFromLB(
        uint24 newLower,
        uint24 newUpper,
        uint24 desiredActiveId,
        uint24 slippageActiveId,
        uint256[] memory amountsInY,
        uint256 maxPercentageToAddX,
        uint256 maxPercentageToAddY
    ) external override onlyOperators {
        _withdrawAndApplyAumAnnualFee();

        if (newUpper != 0) {
            (newLower, newUpper) = _adjustRange(newLower, newUpper, desiredActiveId, slippageActiveId);

            (uint256 amountX, uint256 amountY, uint256[] memory distributionX, uint256[] memory distributionY) =
                _getDistributionsAndAmounts(newLower, newUpper, maxPercentageToAddX, maxPercentageToAddY, amountsInY);

            _depositToLB(newLower, newUpper, distributionX, distributionY, amountX, amountY);
        }
    }

    /**
     * @notice Swaps tokens using 1inch.
     * @dev Only the operator can call this function.
     * @param data The data to call the 1inch router with.
     */
    function swap(bytes memory data) external override onlyOperators {
        if (data.length < 0xc4) revert Strategy__InvalidData();

        address dstToken;
        address dstReceiver;

        assembly {
            dstToken := mload(add(data, 0x64))
            dstReceiver := mload(add(data, 0xa4))
        }

        // The src token is checked by the approval.
        if (dstToken != address(_tokenX()) && dstToken != address(_tokenY())) revert Strategy__InvalidDstToken();
        if (dstReceiver != address(this)) revert Strategy__InvalidReceiver();

        (bool success,) = _ONE_INCH_ROUTER.call(data);
        if (!success) revert Strategy__SwapFailed();
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
        _pendingAumAnnualFee = pendingAumAnnualFee;
        _pendingAumAnnualFeeSet = true;

        emit PendingAumAnnualFeeSet(pendingAumAnnualFee);
    }

    /**
     * @notice Resets the pending assets under management annual fee.
     * @dev Only the factory can call this function.
     */
    function resetPendingAumAnnualFee() external override onlyFactory {
        _pendingAumAnnualFeeSet = false;

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
     * @dev Returns the bin step of the pair
     * @return binStep The bin step of the pair
     */
    function _binStep() internal pure returns (uint16 binStep) {
        binStep = _getArgUint16(80);
    }

    /**
     * @dev Returns the ids of the tokens in the range.
     * @param lower The lower end of the range.
     * @param upper The upper end of the range.
     * @return ids The ids of the tokens in the range.
     */
    function _getIds(uint24 lower, uint24 upper) internal pure returns (uint256[] memory ids) {
        uint256 delta = upper - lower + 1;

        ids = new uint256[](delta);

        for (uint256 i; i < delta;) {
            ids[i] = lower + i;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Returns the balances of the contract, including those deposited and the fees not yet collected.
     * @return amountX The balance of token X.
     * @return amountY The balance of token Y.
     */
    function _getBalances() internal view returns (uint256 amountX, uint256 amountY) {
        amountX = _tokenX().balanceOf(address(this));
        amountY = _tokenY().balanceOf(address(this));

        (uint24 lower, uint24 upper) = (_lowerRange, _upperRange);

        if (upper != 0) {
            uint256[] memory ids = _getIds(lower, upper);

            (uint256 depositedX, uint256 depositedY) = _vault().getAmountsOf(ids, address(_pair()));
            (uint256 feesX, uint256 feesY) = _getPendingFees(ids);

            amountX += depositedX + feesX;
            amountY += depositedY + feesY;
        }
    }

    /**
     * @dev Returns the pending fees of the tokens in the range.
     * @param ids The ids of the tokens.
     * @return feesX The pending fees of token X.
     * @return feesY The pending fees of token Y.
     */
    function _getPendingFees(uint256[] memory ids) internal view returns (uint256 feesX, uint256 feesY) {
        (feesX, feesY) = _pair().pendingFees(address(this), ids);
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
        returns (uint24, uint24)
    {
        (,, uint256 activeId) = _pair().getReservesAndId();

        if (desiredActiveId != activeId) {
            uint24 delta;

            if (desiredActiveId > activeId) {
                unchecked {
                    delta = desiredActiveId - uint24(activeId);

                    newLower = newLower > delta ? newLower - delta : 0;
                    newUpper = newUpper > delta ? newUpper - delta : 0;
                }
            } else {
                unchecked {
                    delta = uint24(activeId) - desiredActiveId;

                    newLower = newLower > type(uint24).max - delta ? type(uint24).max : newLower + delta;
                    newUpper = newUpper > type(uint24).max - delta ? type(uint24).max : newUpper + delta;
                }
            }

            if (delta > slippageActiveId) revert Strategy__ActiveIdSlippage();
        }

        return (newLower, newUpper);
    }

    /**
     * @dev Returns the distributions and amounts following the `amountsInY`.
     * @param newLower The lower end of the new range.
     * @param newUpper The upper end of the new range.
     * @param maxPercentageToAddX The maximum percentage of token X to add.
     * @param maxPercentageToAddY The maximum percentage of token Y to add.
     * @param amountsInY The amounts of token, valued in token Y, to add.
     * @return amountX The amount of token X to add.
     * @return amountY The amount of token Y to add.
     * @return distributionX The distribution of token X to add.
     * @return distributionY The distribution of token Y to add.
     */
    function _getDistributionsAndAmounts(
        uint24 newLower,
        uint24 newUpper,
        uint256 maxPercentageToAddX,
        uint256 maxPercentageToAddY,
        uint256[] memory amountsInY
    )
        internal
        view
        returns (uint256 amountX, uint256 amountY, uint256[] memory distributionX, uint256[] memory distributionY)
    {
        uint256 activeId;
        uint256 price;
        uint256 compositionFactor;

        {
            (,, activeId) = _pair().getReservesAndId();
            (uint256 activeX, uint256 activeY) = _pair().getBin(uint24(activeId));

            price = activeId.getPriceFromId(_binStep());
            compositionFactor = activeY == 0 || activeX == 0 ? 1 >> 127 : activeY / ((activeX * price >> 128) + activeY);
        }

        if (newLower <= activeId && activeId <= newUpper) {
            (amountX, amountY, distributionX, distributionY) =
                amountsInY.getDistributions(compositionFactor, price, activeId - newLower);
        } else {
            distributionX = new uint256[](amountsInY.length);
            distributionY = new uint256[](amountsInY.length);

            if (activeId < newLower) {
                amountX = amountsInY.computeDistributionX(distributionX, price, 0, 0, false);
            } else {
                amountY = amountsInY.computeDistributionY(distributionY, 0, amountsInY.length, false);
            }
        }

        uint256 maxAmountX = _tokenX().balanceOf(address(this)) * maxPercentageToAddX / _PRECISION;
        uint256 maxAmountY = _tokenY().balanceOf(address(this)) * maxPercentageToAddY / _PRECISION;

        if (amountX == 0 || amountY == 0) {
            amountX = amountX > maxAmountX ? maxAmountX : amountX;
            amountY = amountY > maxAmountY ? maxAmountY : amountY;
        } else if (amountX > maxAmountX || amountY > maxAmountY) {
            (amountX, amountY) = maxAmountX * amountY > maxAmountY * amountX
                ? (amountX * maxAmountY / amountY, maxAmountY)
                : (maxAmountX, amountY * maxAmountX / amountX);
        }
    }

    /**
     * @dev Sets the range only if it is not already set. Will revert if the range is already set.
     * @param newLower The lower end of the new range.
     * @param newUpper The upper end of the new range.
     */
    function _setRange(uint24 newLower, uint24 newUpper) internal {
        if (newUpper == 0 || newLower > newUpper) revert Strategy__InvalidRange();

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
     * @param distributionX The distribution of token X.
     * @param distributionY The distribution of token Y.
     * @param amountX The amount of token X to deposit.
     * @param amountY The amount of token Y to deposit.
     */
    function _depositToLB(
        uint24 lower,
        uint24 upper,
        uint256[] memory distributionX,
        uint256[] memory distributionY,
        uint256 amountX,
        uint256 amountY
    ) internal {
        if (upper == 0) revert Strategy__InvalidRange();

        uint256 delta = upper - lower + 1;

        if (distributionX.length != delta || distributionY.length != delta) revert Strategy__InvalidDistribution();
        if (amountX == 0 && amountY == 0) revert Strategy__ZeroAmounts();

        _setRange(lower, upper);

        address pair = address(_pair());

        if (amountX > 0) _tokenX().safeTransfer(pair, amountX);
        if (amountY > 0) _tokenY().safeTransfer(pair, amountY);

        ILBPair(pair).mint(_getIds(lower, upper), distributionX, distributionY, address(this));
    }

    /**
     * @dev Collects the fees from the pair.
     * @param ids The ids of the tokens to collect the fees for.
     */
    function _collectFees(uint256[] memory ids) internal {
        (uint256 pendingX, uint256 pendingY) = _getPendingFees(ids);
        if (pendingX > 0 || pendingY > 0) _pair().collectFees(address(this), ids);
    }

    function _withdrawAndApplyAumAnnualFee() internal {
        (uint24 lowerRange, uint24 upperRange) = (_lowerRange, _upperRange);

        if (upperRange > 0) {
            _resetRange();
            (uint256 totalBalanceX, uint256 totalBalanceY) = _withdraw(lowerRange, upperRange, 1, 1);

            if (totalBalanceX > 0 || totalBalanceY > 0) {
                uint256 lastRebalance = _lastRebalance;
                _lastRebalance = block.timestamp.safe64();

                uint256 annualFee = _aumAnnualFee;

                if (annualFee > 0 && block.timestamp > lastRebalance) {
                    address feeRecipient = _factory.getFeeRecipient();

                    uint256 duration = block.timestamp - lastRebalance;
                    duration = duration > 1 days ? duration : 1 days;

                    // Round up the fees
                    uint256 feeX = (totalBalanceX * annualFee * duration + _SCALED_YEAR_SUB_ONE) / _SCALED_YEAR;
                    uint256 feeY = (totalBalanceY * annualFee * duration + _SCALED_YEAR_SUB_ONE) / _SCALED_YEAR;

                    if (feeX > 0) _tokenX().safeTransfer(feeRecipient, feeX);
                    if (feeY > 0) _tokenY().safeTransfer(feeRecipient, feeY);

                    emit AumFeeCollected(msg.sender, totalBalanceX, totalBalanceY, feeX, feeY);
                }

                if (_pendingAumAnnualFeeSet) {
                    _pendingAumAnnualFeeSet = false;

                    uint16 pendingAumAnnualFee = _pendingAumAnnualFee;
                    _aumAnnualFee = pendingAumAnnualFee;

                    emit AumAnnualFeeSet(pendingAumAnnualFee);
                }
            }
        }
    }

    /**
     * @dev Withdraws tokens from the pair.
     * @param removedLower The lower end of the range to remove.
     * @param removedUpper The upper end of the range to remove.
     * @param shares The amount of shares to withdraw.
     * @param totalShares The total amount of shares.
     * @return amountX The amount of token X withdrawn.
     * @return amountY The amount of token Y withdrawn.
     */
    function _withdraw(uint24 removedLower, uint24 removedUpper, uint256 shares, uint256 totalShares)
        internal
        returns (uint256 amountX, uint256 amountY)
    {
        if (removedUpper == 0) {
            uint256 balanceX = IERC20Upgradeable(_tokenX()).balanceOf(address(this));
            uint256 balanceY = IERC20Upgradeable(_tokenY()).balanceOf(address(this));

            return (shares * balanceX / totalShares, shares * balanceY / totalShares);
        } else {
            (uint256 balanceX, uint256 balanceY, uint256 withdrawnX, uint256 withdrawnY) =
                _withdrawFromLB(removedLower, removedUpper, shares, totalShares);

            amountX = withdrawnX + shares * balanceX / totalShares;
            amountY = withdrawnY + shares * balanceY / totalShares;
        }
    }

    function _withdrawFromLB(uint24 removedLower, uint24 removedUpper, uint256 shares, uint256 totalShares)
        internal
        returns (uint256 balanceX, uint256 balanceY, uint256 withdrawnX, uint256 withdrawnY)
    {
        uint256 delta = removedUpper - removedLower + 1;

        uint256[] memory ids = new uint256[](delta);
        uint256[] memory amounts = new uint256[](delta);

        address pair = address(_pair());

        uint256 length = 0;
        for (uint256 i; i < delta;) {
            uint256 id = removedLower + i;
            uint256 amount = shares * ILBToken(pair).balanceOf(address(this), id) / totalShares;

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

        if (length != delta) {
            assembly {
                mstore(ids, length)
                mstore(amounts, length)
            }
        }

        ILBToken(pair).safeBatchTransferFrom(address(this), pair, ids, amounts);
        _collectFees(new uint256[](0));

        balanceX = IERC20Upgradeable(_tokenX()).balanceOf(address(this));
        balanceY = IERC20Upgradeable(_tokenY()).balanceOf(address(this));

        if (length == 0) return (balanceX, balanceY, 0, 0);

        ILBPair(pair).burn(ids, amounts, address(this));

        withdrawnX = IERC20Upgradeable(_tokenX()).balanceOf(address(this)) - balanceX;
        withdrawnY = IERC20Upgradeable(_tokenY()).balanceOf(address(this)) - balanceY;
    }
}
