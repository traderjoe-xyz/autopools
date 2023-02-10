// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {BinHelper} from "joe-v2/libraries/BinHelper.sol";
import {Clone} from "clones-with-immutable-args/Clone.sol";
import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ILBPair} from "joe-v2/interfaces/ILBPair.sol";
import {ILBToken} from "joe-v2/interfaces/ILBToken.sol";
import {ILBToken} from "joe-v2/interfaces/ILBToken.sol";
import {LiquidityAmounts} from "joe-v2-periphery/periphery/LiquidityAmounts.sol";
import {Math512Bits} from "joe-v2/libraries/Math512Bits.sol";
import {SafeERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {IStrategy} from "./interfaces/IStrategy.sol";
import {IVaultFactory} from "./interfaces/IVaultFactory.sol";
import {Encoded} from "./libraries/Encoded.sol";

contract Strategy is Clone, IStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LiquidityAmounts for address;
    using Encoded for bytes32;

    address private constant ONE_INCH_ROUTER = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    uint256 private constant _PRECISION = 1e18;
    uint256 private constant _BASIS_POINTS = 1e4;

    uint256 private constant _OFFSET_LOWER_RANGE = 0;
    uint256 private constant _OFFSET_UPPER_RANGE = 24;
    uint256 private constant _OFFSET_STRATEGIST_FEE = 48;
    uint256 private constant _OFFSET_OPERATOR = 54;

    bytes32 private _parameters;

    IVaultFactory private immutable _factory;

    modifier onlyFactory() {
        if (msg.sender != address(_factory)) revert Strategy__OnlyFactory();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != _vault()) revert Strategy__OnlyFactory();
        _;
    }

    modifier onlyOperators() {
        address operator = _decodeOperator(_parameters);
        if (msg.sender != operator || msg.sender != _factory.getDefaultOperator()) revert Strategy__Unhautorized();
        _;
    }

    modifier onlyValidData(bytes memory data) {
        if (data.length < 0x84) revert Strategy__InvalidData();

        address srcToken;
        address dstToken;
        address dstReceiver;

        assembly {
            srcToken := mload(add(data, 0x24))
            dstToken := mload(add(data, 0x44))
            dstReceiver := mload(add(data, 0x64))
        }

        address tokenX = address(_tokenX());
        address tokenY = address(_tokenY());

        if (srcToken != tokenX && srcToken != tokenY) revert Strategy__InvalidSrcToken();
        if (dstToken != tokenX && dstToken != tokenY) revert Strategy__InvalidDstToken();
        if (dstReceiver != address(this)) revert Strategy__InvalidReceiver();

        _;
    }

    constructor(IVaultFactory factory) {
        _factory = factory;
    }

    function getVault() external pure override returns (address) {
        return _vault();
    }

    function getPair() external pure override returns (ILBPair) {
        return _pair();
    }

    function getTokenX() external pure override returns (IERC20Upgradeable) {
        return _tokenX();
    }

    function getTokenY() external pure override returns (IERC20Upgradeable) {
        return _tokenY();
    }

    function getRange() external view override returns (uint24 low, uint24 upper) {
        (low, upper) = _decodeRange(_parameters);
    }

    function getOperator() external view override returns (address operator) {
        operator = _decodeOperator(_parameters);
    }

    function getBalances() external view override returns (uint256 amountX, uint256 amountY) {
        return _getBalances();
    }

    function getPendingFees() external view override returns (uint256 amountX, uint256 amountY) {
        (uint24 low, uint24 upper) = _decodeRange(_parameters);
        return _getPendingFees(_getIds(low, upper));
    }

    function getStrategistFee() external view override returns (uint256) {
        return _decodeStrategistFee(_parameters);
    }

    function withdraw(uint256 shares, uint256 totalShares, address to)
        external
        override
        onlyVault
        returns (uint256 amountX, uint256 amountY)
    {
        bytes32 parameters = _parameters;

        (uint24 low, uint24 upper) = _decodeRange(parameters);
        (amountX, amountY) = _withdraw(low, upper, shares, totalShares, _decodeStrategistFee(parameters));

        _tokenX().safeTransfer(to, amountX);
        _tokenY().safeTransfer(to, amountY);
    }

    function expandRange(
        uint24 addedLow,
        uint24 addedUpper,
        uint256[] calldata distributionX,
        uint256[] calldata distributionY,
        uint256 amountX,
        uint256 amountY
    ) external override onlyOperators {
        uint256 delta = addedUpper - addedLow + 1;
        if (distributionX.length != delta || distributionY.length != delta) revert Strategy__InvalidDistribution();

        _parameters = _expand(_parameters, addedLow, addedUpper);

        uint256[] memory ids = _getIds(addedLow, addedUpper);

        _tokenX().safeTransfer(address(_pair()), amountX);
        _tokenY().safeTransfer(address(_pair()), amountY);

        ILBPair(_pair()).mint(ids, distributionX, distributionY, address(this));
    }

    function shrinkRange(uint24 removedLow, uint24 removedUpper, uint256 percentageToRemove)
        external
        override
        onlyOperators
    {
        bytes32 parameters = _parameters;

        uint256 fee = _decodeStrategistFee(parameters);
        _parameters = _shrink(parameters, removedLow, removedUpper);

        _withdraw(removedLow, removedUpper, percentageToRemove, _PRECISION, fee);
    }

    function collectFees() external override {
        bytes32 parameters = _parameters;

        (uint24 low, uint24 upper) = _decodeRange(parameters);
        _collectFees(_getIds(low, upper), _decodeStrategistFee(parameters));
    }

    function swap(bytes memory data) external override onlyValidData(data) onlyOperators {
        (bool success,) = ONE_INCH_ROUTER.call(data);
        if (!success) revert Strategy__SwapFailed();
    }

    function setOperator(address operator) external override onlyFactory {
        _parameters = _encodeOperator(_parameters, operator);

        emit OperatorSet(operator);
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
     * @param low The low end of the range.
     * @param upper The upper end of the range.
     * @return newParameters The encoded parameters.
     */
    function _encodeRange(bytes32 parameters, uint24 low, uint24 upper) internal pure returns (bytes32 newParameters) {
        if (low > upper) revert Strategy__InvalidRange();

        newParameters = parameters.set(low, Encoded.MASK_UINT24, _OFFSET_LOWER_RANGE);
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
     * @return low The low end of the range.
     * @return upper The upper end of the range.
     */
    function _decodeRange(bytes32 parameters) internal pure returns (uint24 low, uint24 upper) {
        low = parameters.decodeUint24(_OFFSET_LOWER_RANGE);
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
     * The added range must be outside the existing range and adjacent to the existing range.
     * If the new range is completely inside the existing range, the existing range will be returned.
     * @param parameters The current encoded parameters.
     * @param addedLow The low end of the range to add.
     * @param addedUpper The upper end of the range to add.
     * @return The new encoded range.
     */
    function _expand(bytes32 parameters, uint24 addedLow, uint24 addedUpper) internal pure returns (bytes32) {
        (uint24 previousLow, uint24 previousUpper) = _decodeRange(parameters);
        if (previousUpper == 0) return _encodeRange(parameters, addedLow, addedUpper);

        if (previousLow <= addedLow && previousUpper >= addedUpper) return parameters;

        if (
            (addedLow >= previousLow || uint256(addedUpper) + 1 != previousLow)
                && (addedLow != uint256(previousUpper) + 1 || addedUpper <= previousUpper)
        ) {
            revert Strategy__InvalidAddedRange();
        }

        unchecked {
            uint24 newLow = addedLow == previousUpper + 1 ? previousLow : addedLow;
            uint24 newUpper = addedUpper + 1 == previousLow ? previousUpper : addedUpper;

            return _encodeRange(parameters, newLow, newUpper);
        }
    }

    /**
     * @dev Shrinks the range. The range will be shrunk to exclude the removed range.
     * The removed range must be inside the existing range and adjacent to the existing range.
     * If the removed range is the same as the existing range, the zero range will be returned.
     * @param parameters The current encoded parameters.
     * @param removedLow The low end of the range to remove.
     * @param removedUpper The upper end of the range to remove.
     * @return The new encoded range.
     */
    function _shrink(bytes32 parameters, uint24 removedLow, uint24 removedUpper) internal pure returns (bytes32) {
        (uint24 previousLow, uint24 previousUpper) = _decodeRange(parameters);

        if (removedLow == previousLow && removedUpper == previousUpper) return _encodeRange(parameters, 0, 0);

        if (
            (removedLow <= previousLow || removedUpper != previousUpper)
                && (removedLow != previousLow || removedUpper >= previousUpper)
        ) {
            revert Strategy__InvalidRemovedRange();
        }

        uint24 newLow = removedLow == previousLow ? uint24(_min(removedUpper + 1, previousUpper)) : previousLow;
        uint24 newUpper = removedUpper == previousUpper ? uint24(_max(removedLow - 1, previousLow)) : previousUpper;

        return _encodeRange(parameters, newLow, newUpper);
    }

    /**
     * @dev Returns the minimum of two numbers.
     * @param a The first number.
     * @param b The second number.
     * @return The minimum of the two numbers.
     */
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the maximum of two numbers.
     * @param a The first number.
     * @param b The second number.
     * @return The maximum of the two numbers.
     */
    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the ids of the tokens in the range.
     * @param low The low end of the range.
     * @param upper The upper end of the range.
     * @return ids The ids of the tokens in the range.
     */
    function _getIds(uint24 low, uint24 upper) internal pure returns (uint256[] memory ids) {
        uint256 delta = upper - low + 1;

        ids = new uint256[](delta);

        for (uint256 i; i < delta;) {
            ids[i] = low + i;

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
        amountX = IERC20Upgradeable(_tokenX()).balanceOf(address(this));
        amountY = IERC20Upgradeable(_tokenY()).balanceOf(address(this));

        (uint24 low, uint24 upper) = _decodeRange(_parameters);
        uint256[] memory ids = _getIds(low, upper);

        (uint256 depositedX, uint256 depositedY) = address(this).getAmountsOf(ids, address(_pair()));
        (uint256 feesX, uint256 feesY) = _getPendingFees(ids);

        amountX += depositedX + feesX;
        amountY += depositedY + feesY;
    }

    function _getPendingFees(uint256[] memory ids) internal view returns (uint256 feesX, uint256 feesY) {
        (feesX, feesY) = _pair().pendingFees(address(this), ids);
    }

    /**
     * @dev Collects the fees from the pair.
     * @param ids The ids of the tokens to collect the fees for.
     * @param fee The share of the collected fees to send to the fee recipient.
     */
    function _collectFees(uint256[] memory ids, uint256 fee) internal {
        (uint256 amountX, uint256 amountY) = _pair().collectFees(address(this), ids);

        if (fee > 0) {
            (uint256 feeX, uint256 feeY) = (amountX * fee / _BASIS_POINTS, amountY * fee / _BASIS_POINTS);

            if (feeX == 0 && feeY == 0) return;

            address feeRecipient = _factory.getFeeRecipient();

            if (feeX > 0) _tokenX().safeTransfer(feeRecipient, feeX);
            if (feeY > 0) _tokenX().safeTransfer(feeRecipient, feeY);

            amountX -= feeX;
            amountY -= feeY;
        }
    }

    function _withdraw(uint24 removedLow, uint24 removedUpper, uint256 shares, uint256 totalShares, uint256 fee)
        internal
        returns (uint256 amountX, uint256 amountY)
    {
        uint256 delta = removedUpper - removedLow + 1;

        uint256[] memory ids = new uint256[](delta);
        uint256[] memory amounts = new uint256[](delta);

        address pair = address(_pair());

        for (uint256 i; i < delta;) {
            uint256 id = removedLow + i;

            ids[i] = id;
            amounts[i] = shares * ILBToken(pair).balanceOf(address(this), id) / totalShares;

            unchecked {
                ++i;
            }
        }

        ILBToken(pair).safeBatchTransferFrom(address(this), pair, ids, amounts);
        _collectFees(new uint256[](0), fee);

        uint256 balanceX = IERC20Upgradeable(_tokenX()).balanceOf(address(this));
        uint256 balanceY = IERC20Upgradeable(_tokenY()).balanceOf(address(this));

        ILBPair(pair).burn(ids, amounts, address(this));

        amountX = balanceX - IERC20Upgradeable(_tokenX()).balanceOf(address(this));
        amountY = balanceY - IERC20Upgradeable(_tokenY()).balanceOf(address(this));

        amountX += shares * balanceX / totalShares;
        amountY += shares * balanceY / totalShares;
    }
}
