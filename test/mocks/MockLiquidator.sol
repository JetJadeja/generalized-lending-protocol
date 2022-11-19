pragma solidity 0.8.10;

import {LendingPool, ERC4626, ERC20, PriceOracle, FixedPointMathLib} from "../../src/LendingPool.sol";
import "ds-test/test.sol";

/// @title Mock Liquidator 
/// @dev A test implementation of the Liquidator contract.
contract MockLiquidator is DSTest {
    using FixedPointMathLib for uint256;

    LendingPool pool;
    PriceOracle oracle;

    constructor(LendingPool _pool, PriceOracle _oracle) {
        pool = _pool;
        oracle = _oracle;
    }

    function calculateRepayAmount(address user, uint256 health) public returns (uint256 repayAmount) {

        ERC20[] memory utilized = pool.getCollateral(user);

        ERC20 currentAsset;

        uint256 collateral;

        // Iterate through the user's utilized assets.
        for (uint256 i = 0; i < utilized.length; i++) {

            // Current user utilized asset.
            currentAsset = utilized[i];

            // Calculate the user's maximum borrowable value for this asset.
            // balanceOfUnderlying(asset,user) * ethPrice * collateralFactor.
            collateral = pool.balanceOf(currentAsset, user)
                .mulDivDown(oracle.getUnderlyingPrice(currentAsset), pool.baseUnits(currentAsset));

            repayAmount += collateral
                .mulDivUp(pool.MAX_HEALTH_FACTOR(), health) - collateral;
        }
    }


    function liquidate(
        ERC20 borrowedAsset, 
        ERC20 collateralAsset, 
        address borrower, 
        uint256 health) 
    public {
        uint256 repayAmount = calculateRepayAmount(borrower, health);

        pool.liquidateUser(borrowedAsset, collateralAsset, borrower, repayAmount);
    }
}
