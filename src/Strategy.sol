// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {BinHelper} from "joe-v2/libraries/BinHelper.sol";
import {Clone} from "clones-with-immutable-args/Clone.sol";
import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ILBPair} from "joe-v2/interfaces/ILBPair.sol";
import {ILBToken} from "joe-v2/interfaces/ILBToken.sol";
import {ILBToken} from "joe-v2/interfaces/ILBToken.sol";
import {LiquidityAmounts} from "joe-v2-periphery/periphery/LiquidityAmounts.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {IStrategy} from "./interfaces/IStrategy.sol";
import {IVaultFactory} from "./interfaces/IVaultFactory.sol";
import {Encoded} from "./libraries/Encoded.sol";
import {Math} from "./libraries/Math.sol";
import {Range} from "./libraries/Range.sol";

/**
 * @title Liquidity Book Strategy contract
 * @author Trader Joe
 * @notice This contract is used to interact with the Liquidity Book Pair contract.
 * It is used to manage the liquidity of the vault.
 * The immutable data should be encoded as follow:
 * - 0x00: 20 bytes: The address of the Vault.
 * - 0x14: 20 bytes: The address of the LB pair.
 * - 0x28: 20 bytes: The address of the token X.
 * - 0x3C: 20 bytes: The address of the token Y.
 */
contract Strategy is Clone, ReentrancyGuardUpgradeable, IStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LiquidityAmounts for address;
    using Encoded for bytes32;
    using Math for uint256;
    using Range for uint24;

    address private constant _ONE_INCH_ROUTER = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    uint256 private constant _PRECISION = 1e18;
    uint256 private constant _BASIS_POINTS = 1e4;

    uint256 private constant _OFFSET_LOWER_RANGE = 0;
    uint256 private constant _OFFSET_UPPER_RANGE = 24;
    uint256 private constant _OFFSET_STRATEGIST_FEE = 48;
    uint256 private constant _OFFSET_OPERATOR = 64;

    bytes32 private _parameters;

    IVaultFactory private immutable _factory;

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
        address operator = _decodeOperator(_parameters);
        if (msg.sender != operator && msg.sender != _factory.getDefaultOperator()) revert Strategy__OnlyOperators();
        _;
    }

    /**
     * @dev Constructor of the contract.
     * @param factory The address of the factory.
     */
    constructor(IVaultFactory factory) {
        _factory = factory;

        _disableInitializers();
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
        (lower, upper) = _decodeRange(_parameters);
    }

    /**
     * @notice Returns the operator of the strategy.
     * @return operator The operator of the strategy.
     */
    function getOperator() external view override returns (address operator) {
        operator = _decodeOperator(_parameters);
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
        (uint24 lower, uint24 upper) = _decodeRange(_parameters);
        return upper == 0 ? (0, 0) : _getPendingFees(_getIds(lower, upper));
    }

    /**
     * @notice Returns the strategist fee of the strategy.
     * This is the fee that is taken on the fees collected by the strategy from LB.
     * @return strategistFee The strategist fee of the strategy.
     */
    function getStrategistFee() external view override returns (uint256) {
        return _decodeStrategistFee(_parameters);
    }

    /**
     * @notice Collect the fees from the LB pool.
     */
    function collectFees() external override {
        bytes32 parameters = _parameters;

        (uint24 lower, uint24 upper) = _decodeRange(parameters);
        if (upper > 0) _collectFees(_getIds(lower, upper), _decodeStrategistFee(parameters));
    }

    /**
     * @notice Withdraw tokens from the strategy and the LB pool.
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
        (uint24 lower, uint24 upper) = _decodeRange(_parameters);
        (amountX, amountY) = _withdraw(lower, upper, shares, totalShares);

        _tokenX().safeTransfer(to, amountX);
        _tokenY().safeTransfer(to, amountY);
    }

    /**
     * @notice Deposit tokens to the LB pool following the distributions.
     * @dev Only the operator can call this function.
     * @param addedLower The lower bound of the range to add.
     * @param addedUpper The upper bound of the range to add.
     * @param desiredActiveId The desired active id.
     * @param slippageActiveId The slippage active id.
     * @param distributionX The distribution of token X.
     * @param distributionY The distribution of token Y.
     * @param percentageToAddX The percentage of token X to add.
     * @param percentageToAddY The percentage of token Y to add.
     */
    function depositWithDistributionsToLB(
        uint24 addedLower,
        uint24 addedUpper,
        uint24 desiredActiveId,
        uint24 slippageActiveId,
        uint256[] memory distributionX,
        uint256[] memory distributionY,
        uint256 percentageToAddX,
        uint256 percentageToAddY
    ) external override onlyOperators {
        (addedLower, addedUpper) = _adjustRange(addedLower, addedUpper, desiredActiveId, slippageActiveId);

        uint256 amountX = percentageToAddX * _tokenX().balanceOf(address(this)) / _PRECISION;
        uint256 amountY = percentageToAddY * _tokenY().balanceOf(address(this)) / _PRECISION;

        _depositToLB(addedLower, addedUpper, distributionX, distributionY, amountX, amountY);
    }

    /**
     * @notice Withdraw tokens from the LB pool.
     * @dev Only the operator can call this function.
     * @param removedLower The lower bound of the range to remove.
     * @param removedUpper The upper bound of the range to remove.
     * @param percentageToRemove The percentage of tokens to remove.
     */
    function withdrawFromLB(uint24 removedLower, uint24 removedUpper, uint256 percentageToRemove)
        external
        override
        onlyOperators
        nonReentrant
    {
        _withdraw(removedLower, removedUpper, percentageToRemove, _PRECISION);
    }

    /**
     * @notice Rebalance the strategy by depositing and withdrawing tokens from the LB pool.
     * It will deposit the tokens following the distributions.
     * @dev Only the operator can call this function.
     * @param removedLower The lower bound of the range to remove.
     * @param removedUpper The upper bound of the range to remove.
     * @param addedLower The lower bound of the range to add.
     * @param addedUpper The upper bound of the range to add.
     * @param desiredActiveId The desired active id.
     * @param slippageActiveId The slippage active id.
     * @param distributionX The distribution of token X.
     * @param distributionY The distribution of token Y.
     * @param percentageToAddX The percentage of token X to add.
     * @param percentageToAddY The percentage of token Y to add.
     */
    function rebalanceWithDistributionsFromLB(
        uint24 removedLower,
        uint24 removedUpper,
        uint24 addedLower,
        uint24 addedUpper,
        uint24 desiredActiveId,
        uint24 slippageActiveId,
        uint256[] memory distributionX,
        uint256[] memory distributionY,
        uint256 percentageToAddX,
        uint256 percentageToAddY
    ) external override onlyOperators {
        _withdraw(removedLower, removedUpper, 1, 1);

        uint256 amountX = percentageToAddX * _tokenX().balanceOf(address(this)) / _PRECISION;
        uint256 amountY = percentageToAddY * _tokenY().balanceOf(address(this)) / _PRECISION;

        (addedLower, addedUpper) = _adjustRange(addedLower, addedUpper, desiredActiveId, slippageActiveId);

        _depositToLB(addedLower, addedUpper, distributionX, distributionY, amountX, amountY);
    }

    /**

        parameters = _expand(parameters, addedLower, addedUpper);

        uint256 amountX = percentageToAddX * _tokenX().balanceOf(address(this)) / _PRECISION;
        uint256 amountY = percentageToAddY * _tokenY().balanceOf(address(this)) / _PRECISION;

        _depositToLB(addedLower, addedUpper, distributionX, distributionY, amountX, amountY);
    }

    /**
     * @notice Swap tokens using 1inch.
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
     * @notice Set the operator.
     * @dev Only the factory can call this function.
     * @param operator The address of the operator.
     */
    function setOperator(address operator) external override onlyFactory {
        _parameters = _encodeOperator(_parameters, operator);

        emit OperatorSet(operator);
    }

    /**
     * @notice Set the strategist fee.
     * @dev Only the factory can call this function.
     * @param fee The strategist fee.
     */
    function setStrategistFee(uint256 fee) external override onlyFactory {
        if (fee > _BASIS_POINTS) revert Strategy__InvalidFee();

        _parameters = _encodeStrategistFee(_parameters, uint16(fee));

        emit StrategistFeeSet(fee);
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
     * @dev Encodes the range.
     * @param parameters The current encoded parameters
     * @param lower The lower end of the range.
     * @param upper The upper end of the range.
     * @return newParameters The encoded parameters.
     */
    function _encodeRange(bytes32 parameters, uint24 lower, uint24 upper)
        internal
        pure
        returns (bytes32 newParameters)
    {
        if (lower > upper) revert Strategy__InvalidRange();

        newParameters = parameters.set(lower, Encoded.MASK_UINT24, _OFFSET_LOWER_RANGE);
        newParameters = newParameters.set(upper, Encoded.MASK_UINT24, _OFFSET_UPPER_RANGE);
    }

    /**
     * @dev Encodes the fees on collect.
     * @param parameters The current encoded parameters
     * @param strategistFee The fees on collect.
     * @return newParameters The encoded parameters.
     */
    function _encodeStrategistFee(bytes32 parameters, uint16 strategistFee)
        internal
        pure
        returns (bytes32 newParameters)
    {
        return parameters.set(strategistFee, Encoded.MASK_UINT16, _OFFSET_STRATEGIST_FEE);
    }

    /**
     * @dev Encodes the operator.
     * @param parameters The current encoded parameters
     * @param operator The address of the operator.
     * @return newParameters The encoded parameters.
     */
    function _encodeOperator(bytes32 parameters, address operator) internal pure returns (bytes32 newParameters) {
        return parameters.setAddress(operator, _OFFSET_OPERATOR);
    }

    /**
     * @dev Decodes the range.
     * @param parameters The encoded parameters.
     * @return lower The lower end of the range.
     * @return upper The upper end of the range.
     */
    function _decodeRange(bytes32 parameters) internal pure returns (uint24 lower, uint24 upper) {
        lower = parameters.decodeUint24(_OFFSET_LOWER_RANGE);
        upper = parameters.decodeUint24(_OFFSET_UPPER_RANGE);
    }

    /**
     * @dev Decodes the fees on collect.
     * @param parameters The encoded parameters.
     * @return strategistFee The fees on collect.
     */
    function _decodeStrategistFee(bytes32 parameters) internal pure returns (uint16) {
        return parameters.decodeUint16(_OFFSET_STRATEGIST_FEE);
    }

    /**
     * @dev Decodes the operator.
     * @param parameters The encoded parameters.
     * @return operator The address of the operator.
     */
    function _decodeOperator(bytes32 parameters) internal pure returns (address operator) {
        return parameters.decodeAddress(_OFFSET_OPERATOR);
    }

    /**
     * @dev Expands the range. The range will be expanded to include the added range.
     * @param parameters The current encoded parameters.
     * @param addedLower The lower end of the range to add.
     * @param addedUpper The upper end of the range to add.
     * @return The new encoded range.
     */
    function _expand(bytes32 parameters, uint24 addedLower, uint24 addedUpper) internal pure returns (bytes32) {
        (uint24 previousLower, uint24 previousUpper) = _decodeRange(parameters);
        (uint256 newLower, uint256 newUpper) = previousLower.expands(previousUpper, addedLower, addedUpper);

        return _encodeRange(parameters, uint24(newLower), uint24(newUpper));
    }

    /**
     * @dev Shrinks the range. The range will be shrunk to exclude the removed range.
     * The removed range must be inside the existing range and adjacent to the existing range.
     * If the removed range is the same as the existing range, the zero range will be returned.
     * @param parameters The current encoded parameters.
     * @param removedLower The lower end of the range to remove.
     * @param removedUpper The upper end of the range to remove.
     * @return The new encoded range.
     */
    function _shrink(bytes32 parameters, uint24 removedLower, uint24 removedUpper) internal pure returns (bytes32) {
        (uint24 previousLower, uint24 previousUpper) = _decodeRange(parameters);
        (uint256 newLower, uint256 newUpper) = previousLower.shrinks(previousUpper, removedLower, removedUpper);

        return _encodeRange(parameters, uint24(newLower), uint24(newUpper));
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
        IERC20Upgradeable tokenX = _tokenX();
        IERC20Upgradeable tokenY = _tokenY();

        address vault = _vault();

        amountX = tokenX.balanceOf(address(this)) + tokenX.balanceOf(vault);
        amountY = tokenY.balanceOf(address(this)) + tokenY.balanceOf(vault);

        (uint24 lower, uint24 upper) = _decodeRange(_parameters);

        if (upper != 0) {
            uint256[] memory ids = _getIds(lower, upper);

            (uint256 depositedX, uint256 depositedY) = address(vault).getAmountsOf(ids, address(_pair()));
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
        (feesX, feesY) = _pair().pendingFees(address(_vault()), ids);
    }

    /**
     * @dev Adjusts the range if the active id is different from the desired active id.
     * Will revert if the active id is not within the desired active id and the slippage.
     * @param addedLower The lower end of the range to add.
     * @param addedUpper The upper end of the range to add.
     * @param desiredActiveId The desired active id.
     * @param slippageActiveId The allowed slippage of the active id.
     */
    function _adjustRange(uint24 addedLower, uint24 addedUpper, uint24 desiredActiveId, uint24 slippageActiveId)
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

                    addedLower = addedLower > delta ? addedLower - delta : 0;
                    addedUpper = addedUpper > delta ? addedUpper - delta : 0;
                }
            } else {
                unchecked {
                    delta = uint24(activeId) - desiredActiveId;

                    addedLower = addedLower > type(uint24).max - delta ? type(uint24).max : addedLower + delta;
                    addedUpper = addedUpper > type(uint24).max - delta ? type(uint24).max : addedUpper + delta;
                }
            }

            if (delta > slippageActiveId) revert Strategy__ActiveIdSlippage();
        }

        return (addedLower, addedUpper);
    }


    /**
     * @dev Deposits tokens into the pair.
     * @param addedLower The lower end of the range to add.
     * @param addedUpper The upper end of the range to add.
     * @param distributionX The distribution of token X.
     * @param distributionY The distribution of token Y.
     * @param amountX The amount of token X to deposit.
     * @param amountY The amount of token Y to deposit.
     */
    function _depositToLB(
        uint24 addedLower,
        uint24 addedUpper,
        uint256[] memory distributionX,
        uint256[] memory distributionY,
        uint256 amountX,
        uint256 amountY
    ) internal {
        if (addedLower == 0) revert Strategy__InvalidRange();

        _parameters = _expand(_parameters, addedLower, addedUpper);

        uint256 delta = addedUpper - addedLower + 1;

        if (distributionX.length != delta || distributionY.length != delta) revert Strategy__InvalidDistribution();
        if (amountX == 0 && amountY == 0) revert Strategy__ZeroAmounts();

        address pair = address(_pair());

        if (amountX > 0) _tokenX().safeTransfer(pair, amountX);
        if (amountY > 0) _tokenY().safeTransfer(pair, amountY);

        ILBPair(pair).mint(_getIds(addedLower, addedUpper), distributionX, distributionY, _vault());
    }

    /**
     * @dev Collects the fees from the pair.
     * @param ids The ids of the tokens to collect the fees for.
     * @param fee The share of the collected fees to send to the fee recipient.
     */
    function _collectFees(uint256[] memory ids, uint256 fee) internal {
        address vault = _vault();

        (uint256 pendingX, uint256 pendingY) = _getPendingFees(ids);
        if (pendingX > 0 || pendingY > 0) _pair().collectFees(vault, ids);

        (IERC20Upgradeable tokenX, IERC20Upgradeable tokenY) = (_tokenX(), _tokenY());
        (uint256 vaultX, uint256 vaultY) = (tokenX.balanceOf(vault), tokenY.balanceOf(vault));

        uint256 feeX;
        uint256 feeY;

        address feeRecipient = _factory.getFeeRecipient();

        if (vaultX > 0) {
            feeX = vaultX * fee / _BASIS_POINTS;

            if (feeX > 0) {
                vaultX -= feeX;
                tokenX.safeTransferFrom(vault, feeRecipient, feeX);
            }

            tokenX.safeTransferFrom(vault, address(this), vaultX);
        }

        if (vaultY > 0) {
            feeY = vaultY * fee / _BASIS_POINTS;

            if (feeY > 0) {
                vaultY -= feeY;
                tokenY.safeTransferFrom(vault, feeRecipient, feeY);
            }

            tokenY.safeTransferFrom(vault, address(this), vaultY);
        }

        emit FeesCollected(msg.sender, feeRecipient, vaultX, vaultY, feeX, feeY);
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
            bytes32 parameters = _parameters;

            if (shares == totalShares) _parameters = _shrink(parameters, removedLower, removedUpper);

            uint256 delta = removedUpper - removedLower + 1;

            uint256[] memory ids = new uint256[](delta);
            uint256[] memory amounts = new uint256[](delta);

            address pair = address(_pair());
            address vault = _vault();

            uint256 length = 0;
            for (uint256 i; i < delta;) {
                uint256 id = removedLower + i;
                uint256 amount = shares * ILBToken(pair).balanceOf(vault, id) / totalShares;

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

            ILBToken(pair).safeBatchTransferFrom(vault, pair, ids, amounts);
            _collectFees(new uint256[](0), _decodeStrategistFee(parameters));

            uint256 balanceX = IERC20Upgradeable(_tokenX()).balanceOf(address(this));
            uint256 balanceY = IERC20Upgradeable(_tokenY()).balanceOf(address(this));

            ILBPair(pair).burn(ids, amounts, address(this));

            amountX = IERC20Upgradeable(_tokenX()).balanceOf(address(this)) - balanceX;
            amountY = IERC20Upgradeable(_tokenY()).balanceOf(address(this)) - balanceY;

            amountX += shares * balanceX / totalShares;
            amountY += shares * balanceY / totalShares;
        }
    }
}
