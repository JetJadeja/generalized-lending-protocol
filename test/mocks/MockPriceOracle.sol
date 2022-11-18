pragma solidity 0.8.10;

/// TODO: Should not have to import erc20 from here.
import {ERC20} from "solmate/utils/SafeTransferLib.sol";

/// @title Mock Price Oracle
/// @dev This contract is used to replicate a Price Oracle contract
/// for unit tests.
contract MockPriceOracle {
    mapping(ERC20 => uint256) public prices;

    function updatePrice(ERC20 asset, uint256 price) external {
        prices[asset] = price;
    }

    function getUnderlyingPrice(ERC20 asset) public view returns (uint256) {
        return prices[asset];
    }
}
