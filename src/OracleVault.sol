// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {Math512Bits} from "joe-v2/libraries/Math512Bits.sol";

import {BaseVault} from "./BaseVault.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {IOracleVault} from "./interfaces/IOracleVault.sol";
import {IVaultFactory} from "./interfaces/IVaultFactory.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";

/**
 * @title Liquidity Book Oracle Vault contract
 * @author Trader Joe
 * @notice This contract is used to interact with the Liquidity Book Pair contract.
 * The two tokens of the pair has to have an oracle.
 * The oracle is used to get the price of the token X in token Y.
 * The price is used to value the balance of the strategy and mint shares accordingly.
 * The immutable data should be encoded as follow:
 * - 0x00: 20 bytes: The address of the LB pair.
 * - 0x14: 20 bytes: The address of the token X.
 * - 0x28: 20 bytes: The address of the token Y.
 * - 0x3C: 1 bytes: The decimals of the token X.
 * - 0x3D: 1 bytes: The decimals of the token Y.
 * - 0x3E: 20 bytes: The address of the oracle of the token X.
 * - 0x52: 20 bytes: The address of the oracle of the token Y.
 */
contract OracleVault is BaseVault, IOracleVault {
    using Math512Bits for uint256;

    uint256 private constant _PRICE_OFFSET = 128;

    /**
     * @dev Constructor of the contract.
     * @param factory Address of the factory.
     */
    constructor(IVaultFactory factory) BaseVault(factory) {}

    /**
     * @dev Returns the address of the oracle of the token X.
     * @return oracleX The address of the oracle of the token X.
     */
    function getOracleX() external pure override returns (IAggregatorV3 oracleX) {
        return _dataFeedX();
    }

    /**
     * @dev Returns the address of the oracle of the token Y.
     * @return oracleY The address of the oracle of the token Y.
     */
    function getOracleY() external pure override returns (IAggregatorV3 oracleY) {
        return _dataFeedY();
    }

    /**
     * @dev Returns the price of token X in token Y, in 128.128 binary fixed point format.
     * @return price The price of token X in token Y in 128.128 binary fixed point format.
     */
    function getPrice() external view override returns (uint256 price) {
        return _getPrice();
    }

    /**
     * @dev Returns the data feed of the token X.
     * @return dataFeedX The data feed of the token X.
     */
    function _dataFeedX() internal pure returns (IAggregatorV3 dataFeedX) {
        return IAggregatorV3(_getArgAddress(62));
    }

    /**
     * @dev Returns the data feed of the token Y.
     * @return dataFeedY The data feed of the token Y.
     */
    function _dataFeedY() internal pure returns (IAggregatorV3 dataFeedY) {
        return IAggregatorV3(_getArgAddress(82));
    }

    /**
     * @dev Returns the price of a token using its oracle.
     * @param dataFeed The data feed of the token.
     * @return uintPrice The oracle latest answer.
     */
    function _getOraclePrice(IAggregatorV3 dataFeed) internal view returns (uint256 uintPrice) {
        (, int256 price,,,) = dataFeed.latestRoundData();

        if (price <= 0 || (uintPrice = uint256(price)) > type(uint128).max) revert OracleVault__InvalidPrice();
    }

    /**
     * @dev Returns the price of token X in token Y.
     * WARNING: Both oracles needs to return the same decimals and use the same quote currency.
     * @return price The price of token X in token Y.
     */
    function _getPrice() internal view returns (uint256 price) {
        uint256 scaledPriceX = _getOraclePrice(_dataFeedX()) * 10 ** _decimalsY();
        uint256 scaledPriceY = _getOraclePrice(_dataFeedY()) * 10 ** _decimalsX();

        // Essentially does `price = (priceX / 1eDecimalsX) / (priceY / 1eDecimalsY)`
        // with 128.128 binary fixed point arithmetic.
        price = scaledPriceX.shiftDivRoundDown(_PRICE_OFFSET, scaledPriceY);

        if (price == 0) revert OracleVault__InvalidPrice();
    }

    /**
     * @dev Returns the shares that will be minted when depositing `expectedAmountX` of token X and
     * `expectedAmountY` of token Y. The effective amounts will never be greater than the input amounts.
     * @param strategy The strategy to deposit to.
     * @param amountX The amount of token X to deposit.
     * @param amountY The amount of token Y to deposit.
     * @return shares The amount of shares that will be minted.
     * @return effectiveX The effective amount of token X that will be deposited.
     * @return effectiveY The effective amount of token Y that will be deposited.
     */
    function _previewShares(IStrategy strategy, uint256 amountX, uint256 amountY)
        internal
        view
        override
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY)
    {
        if (amountX == 0 && amountY == 0) return (0, 0, 0);

        uint256 price = _getPrice();
        uint256 totalShares = totalSupply();

        uint256 valueInY = _getValueInY(price, amountX, amountY);

        if (totalShares == 0) return (valueInY * _SHARES_PRECISION, amountX, amountY);

        (uint256 totalX, uint256 totalY) = _getBalances(strategy);
        uint256 totalValueInY = _getValueInY(price, totalX, totalY);

        shares = valueInY.mulDivRoundDown(totalShares, totalValueInY);

        return (shares, amountX, amountY);
    }

    /**
     * @dev Returns the value of amounts in token Y.
     * @param price The price of token X in token Y.
     * @param amountX The amount of token X.
     * @param amountY The amount of token Y.
     * @return valueInY The value of amounts in token Y.
     */
    function _getValueInY(uint256 price, uint256 amountX, uint256 amountY) internal pure returns (uint256 valueInY) {
        uint256 amountXInY = price.mulShiftRoundDown(amountX, _PRICE_OFFSET);
        return amountXInY + amountY;
    }
}
