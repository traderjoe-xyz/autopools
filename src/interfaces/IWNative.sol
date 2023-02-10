// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IWNative is IERC20Upgradeable {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}
