pragma solidity 0.8.10;

import {LendingPool, ERC4626, ERC20} from "../../src/LendingPool.sol";
import "ds-test/test.sol";

/// @title Mock Flash Borrower
/// @dev A test implementation of the FlashBorrower contract.
contract MockFlashBorrower is DSTest {
    /// @dev Called by the LendingPool contract after a flash loan.
    function execute(uint256 amount, bytes memory data) external {
        // Retrieve the asset from the data.
        ERC20 asset = ERC20(abi.decode(data, (address)));

        // Get the address of the Vault.
        ERC4626 vault = LendingPool(msg.sender).vaults(asset);

        // Approve tokens to the Vault.
        asset.approve(address(vault), amount);

        // Deposit tokens back into the Vault contract on behalf of the Lending Pool.
        vault.deposit(amount, msg.sender);
    }
}
