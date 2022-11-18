pragma solidity 0.8.10;

import {FusePool, ERC4626, ERC20} from "../../FusePool.sol";
import {FlashBorrower} from "../../interface/FlashBorrower.sol";
import "ds-test/test.sol";

/// @title Mock Flash Borrower 2
/// @dev A test implementation of the FlashBorrower contract.
contract MockFlashBorrower2 is DSTest {
    /// @dev Called by the FusePool contract after a flash loan.
    function execute(uint256 amount, bytes memory data) external {
        // Retrieve the asset from the data.
        ERC20 asset = ERC20(abi.decode(data, (address)));

        // Get the Fuse Pool.
        FusePool pool = FusePool(msg.sender);

        // Get the address of the Vault.
        ERC4626 vault = pool.vaults(asset);

        // Try to call flashBorrow again.
        pool.flashBorrow(
            FlashBorrower(address(this)), 
            data,
            asset,
            amount
        );

        // Approve tokens to the Vault.
        asset.approve(address(vault), amount);

        // Deposit tokens back into the Vault contract on behalf of the Fuse Pool.
        vault.deposit(amount, msg.sender);
    }
}
