// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {Uint256x256Math} from "joe-v2/libraries/math/Uint256x256Math.sol";

import {BaseVault} from "./BaseVault.sol";
import {OracleVault} from "./OracleVault.sol";
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
 * - 0x66: 1 bytes: The decimals of the oracle of the token X.
 * - 0x67: 1 bytes: The decimals of the oracle of the token Y.
 */
contract CustomOracleVault is OracleVault {
    using Uint256x256Math for uint256;

    constructor(IVaultFactory factory) OracleVault(factory) {}

    /**
     * @dev Returns the price of token X in token Y.
     * @return price The price of token X in token Y.
     */
    function _getPrice() internal view override returns (uint256 price) {
        uint256 scaledPriceX = _getOraclePrice(_dataFeedX()) * 10 ** (_decimalsY() + _oracleDecimalsY());
        uint256 scaledPriceY = _getOraclePrice(_dataFeedY()) * 10 ** (_decimalsX() + _oracleDecimalsX());

        // Essentially does `price = (priceX / 1eDecimalsX) / (priceY / 1eDecimalsY)`
        // with 128.128 binary fixed point arithmetic.
        price = scaledPriceX.shiftDivRoundDown(_PRICE_OFFSET, scaledPriceY);

        if (price == 0) revert OracleVault__InvalidPrice();
    }

    /**
     * @dev Returns the decimals of the data feed of the token X.
     * @return decimals The decimals of the data feed of the token X.
     */
    function _oracleDecimalsX() internal pure virtual returns (uint8 decimals) {
        return _getArgUint8(102);
    }

    /**
     * @dev Returns the decimals of the data feed of the token Y.
     * @return decimals The decimals of the data feed of the token Y.
     */
    function _oracleDecimalsY() internal pure virtual returns (uint8 decimals) {
        return _getArgUint8(103);
    }
}
