// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FusePool, FusePoolFactory} from "../FusePoolFactory.sol";

import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";
import {PriceOracle} from "../interface/PriceOracle.sol";

import {Authority} from "solmate/auth/Auth.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

/// @title Fuse Pool Factory Test Contract
contract FusePoolFactoryTest is DSTestPlus {
    // Used variables.
    FusePoolFactory factory;
    
    function setUp() public {
        // Deploy Fuse Pool Factory.
        factory = new FusePoolFactory(address(this), Authority(address(0)));
    }

    function testDeployFusePool() public {
        (FusePool pool, uint256 id) = factory.deployFusePool("Test Pool");

        // Assertions.
        assertEq(factory.poolNumber(), 1);
        assertEq(pool.name(), "Test Pool");
        assertEq(pool.owner(), address(this));

        assertEq(address(pool), address(factory.getPoolFromNumber(id)));
        assertGt(address(pool).code.length, 0);
    }

    function testPoolNumberIncrement() public {
        (FusePool pool1, uint256 id1) = factory.deployFusePool("Test Pool 1");
        (FusePool pool2, uint256 id2) = factory.deployFusePool("Test Pool 2");

        // Assertions.
        assertFalse(id1 == id2);
        assertFalse(pool1 == pool2);
        assertEq(factory.poolNumber(), 2);
    }
}
