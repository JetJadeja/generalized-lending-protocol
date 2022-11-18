pragma solidity 0.8.10;

// TODO: Should not have to import ERC20 from here.
import {ERC20} from "solmate/utils/SafeTransferLib.sol";

/// @title Price Oracle Interface.
/// @author Jet Jadeja <jet@rari.capital>
interface PriceOracle {
    /// @notice Get the price of an asset.
    /// @param asset The address of the underlying asset.
    /// @dev The underlying asset price is scaled by 1e18.
    function getUnderlyingPrice(ERC20 asset) external view returns (uint256);
}
