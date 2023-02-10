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

    uint256 private constant _SCALE_OFFSET = 128;

    constructor(IVaultFactory factory) BaseVault(factory) {}

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
     * @return price The oracle latest answer.
     */
    function _getOraclePrice(IAggregatorV3 dataFeed) internal view returns (uint256) {
        (, int256 price,,,) = dataFeed.latestRoundData();

        if (price <= 0) revert OracleVault__InvalidPrice();

        return uint256(price);
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
        price = scaledPriceX.shiftDivRoundDown(_SCALE_OFFSET, scaledPriceY);
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
        if (amountX > type(uint128).max || amountY > type(uint128).max) revert OracleVault__AmountsOverflow();
        if (amountX == 0 && amountY == 0) return (0, 0, 0);

        uint256 price = _getPrice();
        uint256 totalShares = totalSupply();

        uint256 valueInY = price * amountX + (amountY << _SCALE_OFFSET);

        if (totalShares == 0) {
            return (valueInY, amountX, amountY);
        }

        (uint256 totalX, uint256 totalY) = _getBalances(strategy);
        if (totalX > type(uint128).max || totalY > type(uint128).max) revert OracleVault__AmountsOverflow();

        uint256 totalValueInY = price * totalX + (totalY << _SCALE_OFFSET);

        shares = valueInY.mulDivRoundDown(totalShares, totalValueInY);

        return (shares, amountX, amountY);
    }
}
