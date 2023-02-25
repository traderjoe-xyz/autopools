// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title Wrapped Native Interface
 * @author Trader Joe
 * @notice Interface used to interact with wNative tokens
 */
interface IWNative is IERC20Upgradeable {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}
