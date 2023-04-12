// SPDX-License-indexentifier: MIT

pragma solidity 0.8.10;

/**
 * @title The Distribution library
 * @author Trader Joe
 * @notice This library is used to compute the distribution of a given amount of tokens.
 */
library Distribution {
    error Distribution__CompositionFactorTooHigh();
    error Distribution__AmountTooHigh();
    error Distribution__PriceTooLow();

    uint256 internal constant PRECISION = 1e18;

    uint256 internal constant OFFSET = 128;
    uint256 internal constant ONE = 1 << OFFSET;

    /**
     * @notice Returns the distribution following a given composition factor, price and amounts valued in Y.
     * @param desiredL The desired liquidity values, which are the amounts of tokens valued in Y.
     * @param compositionFactor The composition factor.
     * @param price The price of the token.
     * @param index The index of the active amount.
     * @return amountX The amount of token X.
     * @return amountY The amount of token Y.
     * @return distributionX The distribution of token X.
     * @return distributionY The distribution of token Y.
     */
    function getDistributions(uint256[] memory desiredL, uint256 compositionFactor, uint256 price, uint256 index)
        internal
        pure
        returns (uint256 amountX, uint256 amountY, uint256[] memory distributionX, uint256[] memory distributionY)
    {
        if (compositionFactor > ONE) revert Distribution__CompositionFactorTooHigh();
        if (price == 0) revert Distribution__PriceTooLow();

        distributionX = new uint256[](desiredL.length);
        distributionY = new uint256[](desiredL.length);

        uint256 activeAmount = desiredL[index];

        if (activeAmount > type(uint128).max) revert Distribution__AmountTooHigh();

        amountY = (activeAmount * compositionFactor) >> OFFSET;
        amountX = ((activeAmount - amountY) << OFFSET) / price;

        distributionX[index] = amountX;
        distributionY[index] = amountY;

        amountX = computeDistributionX(desiredL, distributionX, price, amountX, index, true);
        amountY = computeDistributionY(desiredL, distributionY, amountY, index, true);
    }

    /**
     * @notice Computes the distribution Y following a given composition factor, price and amounts valued in Y.
     * @param desiredL The desired liquidity values, which are the amounts of tokens valued in Y.
     * @param distributionY The distribution of token Y.
     * @param amountY The amount of token Y.
     * @param end The index of the last amount to compute.
     * @param endIsActive Whether the last amount is the active id.
     * @return The amount of token Y.
     */
    function computeDistributionY(
        uint256[] memory desiredL,
        uint256[] memory distributionY,
        uint256 amountY,
        uint256 end,
        bool endIsActive
    ) internal pure returns (uint256) {
        for (uint256 i; i < end;) {
            uint256 amountInY = desiredL[i];
            if (amountInY > type(uint128).max) revert Distribution__AmountTooHigh();

            amountY += amountInY;
            distributionY[i] = amountInY;

            unchecked {
                ++i;
            }
        }

        computeDistribution(distributionY, amountY, 0, endIsActive ? end + 1 : end);

        return amountY;
    }

    /**
     * @notice Computes the distribution X following a given composition factor, price and amounts valued in Y.
     * @param desiredL The desired liquidity values, which are the amounts of tokens valued in Y.
     * @param distributionX The distribution of token X.
     * @param price The price of the token.
     * @param amountX The amount of token X.
     * @param start The index of the first amount to compute.
     * @param startIsActive Whether the first amount is the active id.
     * @return The amount of token X.
     */
    function computeDistributionX(
        uint256[] memory desiredL,
        uint256[] memory distributionX,
        uint256 price,
        uint256 amountX,
        uint256 start,
        bool startIsActive
    ) internal pure returns (uint256) {
        for (uint256 i = startIsActive ? start + 1 : start; i < desiredL.length;) {
            uint256 amountInY = desiredL[i];
            uint256 amountInX = (amountInY << OFFSET) / price;

            if (amountInY > type(uint128).max || amountInX > type(uint128).max) revert Distribution__AmountTooHigh();

            amountX += amountInX;
            distributionX[i] = amountInX;

            unchecked {
                ++i;
            }
        }

        computeDistribution(distributionX, amountX, start, desiredL.length);

        return amountX;
    }

    /**
     * @notice Computes the distribution from a given amount of tokens.
     * Returns the percentage of each amount in the total amount.
     * @param amounts The amounts of tokens to distribute.
     * @param totalAmount The total amount of tokens to distribute.
     * @param start The index of the first amount to compute.
     * @param end The index of the last amount to compute.
     */
    function computeDistribution(uint256[] memory amounts, uint256 totalAmount, uint256 start, uint256 end)
        internal
        pure
    {
        if (totalAmount > 0) {
            for (uint256 i = start; i < end;) {
                amounts[i] = amounts[i] * PRECISION / totalAmount;

                unchecked {
                    ++i;
                }
            }
        }
    }
}
