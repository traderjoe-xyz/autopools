// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

contract MockAggregator is Ownable, IAggregatorV3 {
    int256 price = 1e18;

    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function description() external pure override returns (string memory) {
        return "Mock Aggregator";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 id)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (id, price, block.timestamp, block.timestamp, id);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, price, block.timestamp, block.timestamp, 0);
    }

    function setPrice(int256 _price) external onlyOwner {
        price = _price;
    }
}
