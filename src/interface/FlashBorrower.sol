// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

/// @title Flash Borrower Interface.
/// @dev Interface for the borrower of a flash loan.
interface FlashBorrower {
    /// @dev Called when a flash loan is created.
    function execute(uint256 amount, bytes memory data) external;
}
