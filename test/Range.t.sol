// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../src/libraries/Range.sol";

contract RangeTest is Test {
    using Range for uint256;

    function testFuzz_Contains(uint256 lower, uint256 upper, uint256 value) external {
        vm.assume(lower <= upper);

        bool contains = lower <= value && value <= upper;

        assertEq(lower.contains(upper, value), contains, "testFuzz_Contains::1");
    }

    function testFuzz_ExpandsWhenNoRange(uint256 addedLower, uint256 addedUpper) external {
        vm.assume(addedLower <= addedUpper);

        (uint256 newLower, uint256 newUpper) = uint256(0).expands(0, addedLower, addedUpper);

        assertEq(newLower, addedLower, "testFuzz_ExpandsWhenNoRange::1");
        assertEq(newUpper, addedUpper, "testFuzz_ExpandsWhenNoRange::2");
    }

    function testFuzz_ExpandsWhenContained(uint256 lower, uint256 upper, uint256 addedLower, uint256 addedUpper)
        external
    {
        vm.assume(upper > 0 && lower <= upper && addedLower <= addedUpper);

        bool lowerIsContained = lower <= addedLower && addedLower <= upper;
        bool upperIsContained = lower <= addedUpper && addedUpper <= upper;

        vm.assume(lowerIsContained || upperIsContained);

        uint256 expandedLower = lowerIsContained ? lower : addedLower;
        uint256 expandedUpper = upperIsContained ? upper : addedUpper;

        (uint256 newLower, uint256 newUpper) = lower.expands(upper, addedLower, addedUpper);

        assertEq(newLower, expandedLower, "testFuzz_ExpandsWhenContained::1");
        assertEq(newUpper, expandedUpper, "testFuzz_ExpandsWhenContained::2");
    }

    function testFuzz_ExpandsWhenOverlapping(uint256 lower, uint256 upper, uint256 addedLower, uint256 addedUpper)
        external
    {
        vm.assume(upper > 0 && lower <= upper && addedLower <= addedUpper);

        bool lowerIsOverlapping = addedLower <= lower && lower <= addedUpper;
        bool upperIsOverlapping = addedLower <= upper && upper <= addedUpper;

        vm.assume(lowerIsOverlapping || upperIsOverlapping);

        uint256 expandedLower = lowerIsOverlapping ? addedLower : lower;
        uint256 expandedUpper = upperIsOverlapping ? addedUpper : upper;

        (uint256 newLower, uint256 newUpper) = lower.expands(upper, addedLower, addedUpper);

        assertEq(newLower, expandedLower, "testFuzz_ExpandsWhenOverlapping::1");
        assertEq(newUpper, expandedUpper, "testFuzz_ExpandsWhenOverlapping::2");
    }

    function testFuzz_ExpandsWhenContinuous(uint256 lower, uint256 upper, uint256 addedLower, uint256 addedUpper)
        external
    {
        uint256 upperPlusOne = upper == type(uint256).max ? upper : upper + 1;
        uint256 lowerMinusOne = lower == 0 ? lower : lower - 1;

        addedLower = addedLower % 2 == 0 ? addedLower : upperPlusOne;
        addedUpper = addedUpper % 2 == 0 ? addedUpper : lowerMinusOne;

        vm.assume(
            upper > 0 && lower <= upper && addedLower <= addedUpper
                && (addedLower == upperPlusOne || addedUpper == lowerMinusOne)
        );

        uint256 expandedLower = lower < addedLower ? lower : addedLower;
        uint256 expandedUpper = upper > addedUpper ? upper : addedUpper;

        (uint256 newLower, uint256 newUpper) = lower.expands(upper, addedLower, addedUpper);

        assertEq(newLower, expandedLower, "testFuzz_ExpandsWhenContinuous::1");
        assertEq(newUpper, expandedUpper, "testFuzz_ExpandsWhenContinuous::2");
    }

    function testFuzz_revert_ExpandsWhenDisjoint(uint256 lower, uint256 upper, uint256 addedLower, uint256 addedUpper)
        external
    {
        vm.assume(upper > 0 && lower <= upper && addedLower <= addedUpper);

        bool lowerIsDisjoint = addedUpper < lower;
        bool upperIsDisjoint = upper < addedLower;

        uint256 upperPlusOne = upper == type(uint256).max ? upper : upper + 1;
        uint256 lowerMinusOne = lower == 0 ? lower : lower - 1;

        vm.assume((lowerIsDisjoint || upperIsDisjoint) && addedLower != upperPlusOne && addedUpper != lowerMinusOne);

        vm.expectRevert(Range.Range__InvalidAddedRange.selector);
        lower.expands(upper, addedLower, addedUpper);
    }

    function testFuzz_Shrinks(uint256 lower, uint256 upper, uint256 removedLower, uint256 removedUpper) external {
        vm.assume(
            upper > 0 && lower <= upper && removedLower <= removedUpper && removedLower >= lower
                && removedUpper <= upper && (removedLower == lower || removedUpper == upper)
        );

        uint256 shrunkLower;
        uint256 shrunkUpper;

        if (removedLower == lower && removedUpper == upper) {
            shrunkLower = 0;
            shrunkUpper = 0;
        } else if (removedLower == lower) {
            shrunkLower = removedUpper + 1;
            shrunkUpper = upper;
        } else if (removedUpper == upper) {
            shrunkLower = lower;
            shrunkUpper = removedLower - 1;
        }

        (uint256 newLower, uint256 newUpper) = lower.shrinks(upper, removedLower, removedUpper);

        assertEq(newLower, shrunkLower, "testFuzz_Shrinks::1");
        assertEq(newUpper, shrunkUpper, "testFuzz_Shrinks::2");
    }

    function testFuzz_revert_ShrinksWhenContains(
        uint256 lower,
        uint256 upper,
        uint256 removedLower,
        uint256 removedUpper
    ) external {
        vm.assume(
            upper > 0 && lower <= upper && removedLower <= removedUpper && removedLower >= lower
                && removedUpper <= upper && removedLower != lower && removedUpper != upper
        );

        vm.expectRevert(Range.Range__InvalidRemovedRange.selector);
        lower.shrinks(upper, removedLower, removedUpper);
    }

    function testFuzz_revert_Shrinks(uint256 lower, uint256 upper, uint256 removedLower, uint256 removedUpper)
        external
    {
        vm.assume(lower <= upper && removedLower <= removedUpper && removedLower != lower && removedUpper != upper);

        vm.expectRevert(Range.Range__InvalidRemovedRange.selector);
        lower.shrinks(upper, removedLower, removedUpper);
    }

    function testFuzz_revert_ShrinksOut(uint256 lower, uint256 upper, uint256 removedLower, uint256 removedUpper)
        external
    {
        vm.assume(lower <= upper && removedLower <= removedUpper && (removedLower < lower || removedUpper > upper));

        vm.expectRevert(Range.Range__InvalidRemovedRange.selector);
        lower.shrinks(upper, removedLower, removedUpper);
    }

    function testFuzz_revert_InvalidRange(uint256 lower, uint256 upper) external {
        vm.assume(lower < upper);

        vm.expectRevert(Range.Range__InvalidRange.selector);
        upper.contains(lower, 0);

        vm.expectRevert(Range.Range__InvalidRange.selector);
        upper.expands(lower, 0, 0);

        vm.expectRevert(Range.Range__InvalidRange.selector);
        uint256(0).expands(0, upper, lower);

        vm.expectRevert(Range.Range__InvalidRange.selector);
        upper.shrinks(lower, 0, 0);

        vm.expectRevert(Range.Range__InvalidRange.selector);
        uint256(0).shrinks(0, upper, lower);
    }
}
