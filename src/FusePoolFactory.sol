// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FusePool} from "./FusePool.sol";
import {PriceOracle} from "./interface/PriceOracle.sol";

import {Auth, Authority} from "solmate/auth/Auth.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

/// @title Fuse Pool Factory
/// @author Jet Jadeja <jet@rari.capital>
/// @notice Factory enabling the deployment of Fuse Pools.
contract FusePoolFactory is Auth {
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

    /// @notice A counter indicating how many Fuse Pools have been deployed.
    /// @dev This is used to generate the Fuse Pool ID.
    uint256 public poolNumber;

    /// @dev When a new Fuse Pool is deployed, it will retrieve the
    /// value stored here. This enables the Fuse Pool to be deployed to
    /// an address that does not require the name to determine.
    string public poolDeploymentName;

    /// @notice Emitted when a new Fuse Pool is deployed.
    /// @param pool The newly deployed Fuse Pool.
    /// @param deployer The address of the FusePool deployer.
    event PoolDeployed(uint256 indexed id, FusePool indexed pool, address indexed deployer);

    /// @notice Deploy a new Fuse Pool.
    /// @return pool The address of the newly deployed pool.
    function deployFusePool(string memory name) external returns (FusePool pool, uint256 index) {
        // Calculate pool ID.
        
        // Unchecked is safe here because index will never reach type(uint256).max
        unchecked { index = poolNumber + 1; }

        // Update state variables.
        poolNumber = index;
        poolDeploymentName = name;

        // Deploy the Fuse Pool using the CREATE2 opcode.
        pool = new FusePool{salt: bytes32(index)}();

        // Emit the event.
        emit PoolDeployed(index, pool, msg.sender);

        // Reset the deployment name.
        delete poolDeploymentName;
    }

    /*///////////////////////////////////////////////////////////////
                           POOL RETRIEVAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the address of a Fuse Pool given its ID.
    function getPoolFromNumber(uint256 id) external view returns (FusePool pool) {
        // Retrieve the Fuse Pool.
        return
            FusePool(
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
                                    type(FusePool).creationCode
                                )
                            )
                        )
                    ).fromLast20Bytes() // Convert the CREATE2 hash into an address.
                )
            );
    }
}
