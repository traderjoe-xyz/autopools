// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

/**
 * @title Range library
 * @author Trader Joe
 * @notice This library is used to perform operations on ranges.
 */
library Range {
    error Range__InvalidRange();
    error Range__InvalidAddedRange();
    error Range__InvalidRemovedRange();

    modifier validRange(uint256 lower, uint256 upper) {
        if (lower > upper) revert Range__InvalidRange();
        _;
    }

    modifier validRanges(uint256 lower, uint256 upper, uint256 _lower, uint256 _upper) {
        if (lower > upper || _lower > _upper) revert Range__InvalidRange();
        _;
    }

    /**
     * @dev Checks if a value is contained in a range.
     * @param lower The lower bound of the range.
     * @param upper The upper bound of the range.
     * @param value The value to check.
     * @return True if the value is contained in the range, false otherwise.
     */
    function contains(uint256 lower, uint256 upper, uint256 value)
        internal
        pure
        validRange(lower, upper)
        returns (bool)
    {
        return lower <= value && value <= upper;
    }

    /**
     * @dev Returns the superset of two ranges. The ranges must be contiguous or overlapping.
     * @param lower The lower bound of the first range.
     * @param upper The upper bound of the first range.
     * @param addedLower The lower bound of the second range.
     * @param addedUpper The upper bound of the second range.
     * @return newLower The lower bound of the superset.
     * @return newUpper The upper bound of the superset.
     */
    function expands(uint256 lower, uint256 upper, uint256 addedLower, uint256 addedUpper)
        internal
        pure
        validRanges(lower, upper, addedLower, addedUpper)
        returns (uint256 newLower, uint256 newUpper)
    {
        if (upper == 0) return (addedLower, addedUpper);

        unchecked {
            uint256 upperPlusOne = upper == type(uint256).max ? upper : upper + 1;
            uint256 lowerMinusOne = lower == 0 ? lower : lower - 1;

            if (addedLower > upperPlusOne || addedUpper < lowerMinusOne) {
                revert Range__InvalidAddedRange();
            }
        }

        unchecked {
            newLower = lower < addedLower ? lower : addedLower;
            newUpper = upper > addedUpper ? upper : addedUpper;
        }
    }

    /**
     * @dev Returns the subset of two ranges.
     * The removed range must be contained in the original range and must have the same start or end point.
     * @param lower The lower bound of the range.
     * @param upper The upper bound of the range.
     * @param removedLower The lower bound of the subset.
     * @param removedUpper The upper bound of the subset.
     * @return newLower The lower bound of the subset.
     * @return newUpper The upper bound of the subset.
     */
    function shrinks(uint256 lower, uint256 upper, uint256 removedLower, uint256 removedUpper)
        internal
        pure
        validRanges(lower, upper, removedLower, removedUpper)
        returns (uint256 newLower, uint256 newUpper)
    {
        if (upper == 0 || removedLower > upper || removedUpper < lower || removedLower < lower || removedUpper > upper)
        {
            revert Range__InvalidRemovedRange();
        }

        if (lower == removedLower && upper == removedUpper) {
            (newLower, newUpper) = (0, 0);
        } else if (lower == removedLower) {
            unchecked {
                (newLower, newUpper) = (removedUpper + 1, upper);
            }
        } else if (upper == removedUpper) {
            unchecked {
                (newLower, newUpper) = (lower, removedLower - 1);
            }
        } else {
            revert Range__InvalidRemovedRange();
        }
    }
}
