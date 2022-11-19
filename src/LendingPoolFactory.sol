// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {LendingPool} from "./LendingPool.sol";
import {PriceOracle} from "./interface/PriceOracle.sol";

import {Auth, Authority} from "solmate/auth/Auth.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

/// @title Lending Pool Factory
/// @author Jet Jadeja <jet@pentagon.xyz>
/// @notice Factory used to deploy isolated lending pools.
contract LendingPoolFactory is Auth {
    using Bytes32AddressLib for address;
    using Bytes32AddressLib for bytes32;

    /*///////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a Vault factory.
    /// @param _owner The owner of the factory.
    /// @param _authority The Authority of the factory.
    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {}

    /*///////////////////////////////////////////////////////////////
                           POOL DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice A counter indicating how many LendingPools have been deployed.
    /// @dev This is used to generate the pool ID.
    uint256 public poolNumber;

    /// @dev When a new pool is deployed, it will retrieve the
    /// value stored here. This enables the lending to be deployed to
    /// an address that does not require the name to determine.
    string public poolDeploymentName;

    /// @notice Emitted when a new LendingPool is deployed.
    /// @param pool The newly deployed pool.
    /// @param deployer The address of the LendingPool deployer.
    event PoolDeployed(uint256 indexed id, LendingPool indexed pool, address indexed deployer);

    /// @notice Deploy a new Lending Pool.
    /// @return pool The address of the newly deployed pool.
    function deployLendingPool(string memory name) external returns (LendingPool pool, uint256 index) {
        // Calculate pool ID.
        
        // Unchecked is safe here because index will never reach type(uint256).max
        unchecked { index = poolNumber + 1; }

        // Update state variables.
        poolNumber = index;
        poolDeploymentName = name;

        // Deploy the LendingPool using the CREATE2 opcode.
        pool = new LendingPool{salt: bytes32(index)}();

        // Emit the event.
        emit PoolDeployed(index, pool, msg.sender);

        // Reset the deployment name.
        delete poolDeploymentName;
    }

    /*///////////////////////////////////////////////////////////////
                           POOL RETRIEVAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the address of a pool given its ID.
    function getPoolFromNumber(uint256 id) external view returns (LendingPool pool) {
        // Retrieve the lending pool.
        return
            LendingPool(
                payable(
                    keccak256(
                        abi.encodePacked(
                            // Prefix:
                            bytes1(0xFF),
                            // Creator:
                            address(this),
                            // Salt:
                            bytes32(id),
                            // Bytecode hash:
                            keccak256(
                                abi.encodePacked(
                                    // Deployment bytecode:
                                    type(LendingPool).creationCode
                                )
                            )
                        )
                    ).fromLast20Bytes() // Convert the CREATE2 hash into an address.
                )
            );
    }
}
