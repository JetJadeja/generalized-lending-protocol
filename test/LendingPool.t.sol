// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {LendingPool, LendingPoolFactory} from "src/LendingPoolFactory.sol";

// TODO: I should not have to import ERC20 from here.
import {ERC20} from "solmate/utils/SafeTransferLib.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {Authority} from "solmate/auth/Auth.sol";
import {DSTest} from "ds-test/test.sol";

import {PriceOracle} from "src/interface/PriceOracle.sol";
import {InterestRateModel} from "src/interface/InterestRateModel.sol";
import {FlashBorrower} from "src/interface/FlashBorrower.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "./mocks/MockERC4626.sol";
import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";
import {MockFlashBorrower} from "./mocks/MockFlashBorrower.sol";
import {MockFlashBorrower2} from "./mocks/MockFlashBorrower2.sol";
import {MockInterestRateModel} from "./mocks/MockInterestRateModel.sol";
import {MockLiquidator} from "./mocks/MockLiquidator.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/// @title Lending Pool Factory Test Contract
contract LendingPoolTest is DSTestPlus {
    using FixedPointMathLib for uint256;

    /* Lending Pool Contracts */
    LendingPoolFactory factory;
    LendingPool pool;

    /* Mocks */
    MockERC20 asset;
    MockERC4626 vault;

    MockERC20 borrowAsset;
    MockERC4626 borrowVault;

    MockPriceOracle oracle;
    MockFlashBorrower flashBorrower;
    MockFlashBorrower2 flashBorrower2;
    MockInterestRateModel interestRateModel;
    MockLiquidator liquidator;

    function setUp() public {
        factory = new LendingPoolFactory(address(this), Authority(address(0)));
        (pool, ) = factory.deployLendingPool("Lending Pool Test");

        asset = new MockERC20("Test Token", "TEST", 18);
        vault = new MockERC4626(ERC20(asset), "Test Token Vault", "TEST");
        
        interestRateModel = new MockInterestRateModel();

        pool.configureAsset(asset, vault, LendingPool.Configuration(0.5e18, 0));
        pool.setInterestRateModel(asset, InterestRateModel(address(interestRateModel)));

        oracle = new MockPriceOracle();
        oracle.updatePrice(ERC20(asset), 1e18);
        pool.setOracle(PriceOracle(address(oracle)));

        borrowAsset = new MockERC20("Borrow Test Token", "TBT", 18);
        borrowVault = new MockERC4626(ERC20(borrowAsset), "Borrow Test Token Vault", "TBT");

        pool.configureAsset(borrowAsset, borrowVault, LendingPool.Configuration(0, 1e18));
        pool.setInterestRateModel(borrowAsset, InterestRateModel(address(interestRateModel)));

        liquidator = new MockLiquidator(pool, PriceOracle(address(oracle)));
    }
    
    /*///////////////////////////////////////////////////////////////
                        ORACLE CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testOracleConfiguration() public {
        assertEq(address(PriceOracle(pool.oracle())), address(oracle));
    }

    function testNewOracleConfiguration() public {
        MockPriceOracle newOracle = new MockPriceOracle();
        newOracle.updatePrice(ERC20(asset), 1e18);
        pool.setOracle(PriceOracle(address(newOracle)));
        
        assertEq(address(PriceOracle(pool.oracle())), address(newOracle));
    }
    
    /*///////////////////////////////////////////////////////////////
                    ORACLE CONFIGURATION SANITY CHECKS
    //////////////////////////////////////////////////////////////*/
    
    function testFailNewOracleConfigurationNotOwner() public {
        MockPriceOracle newOracle = new MockPriceOracle();
        newOracle.updatePrice(ERC20(asset), 1e18);

        hevm.prank(address(0xBABE));
        pool.setOracle(PriceOracle(address(newOracle)));
    }

    /*///////////////////////////////////////////////////////////////
                        IRM CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testIRMConfiguration() public {
        assertEq(address(pool.interestRateModels(asset)), address(interestRateModel));
    }

    function testNewIRMConfiguration() public {
        MockInterestRateModel newInterestRateModel = new MockInterestRateModel();
        pool.setInterestRateModel(asset, InterestRateModel(address(newInterestRateModel)));
        
        assertEq(address(pool.interestRateModels(asset)), address(newInterestRateModel));
    }
    
    /*///////////////////////////////////////////////////////////////
                     IRM CONFIGURATION SANITY CHECKS
    //////////////////////////////////////////////////////////////*/

    function testFailNewIRMConfigurationNotOwner() public {
        
        MockInterestRateModel newInterestRateModel = new MockInterestRateModel();
        hevm.prank(address(0xBABE));
        pool.setInterestRateModel(asset, InterestRateModel(address(newInterestRateModel)));
    }

    /*///////////////////////////////////////////////////////////////
                        ASSET CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testAssetConfiguration() public {
        (uint256 lendFactor, uint256 borrowFactor) = pool.configurations(asset);

        assertEq(lendFactor, 0.5e18);
        assertEq(borrowFactor, 0);
        assertEq(pool.baseUnits(asset), 1e18);
        assertEq(address(pool.vaults(asset)), address(vault));
    }

    function testNewAssetConfiguration() public {
        MockERC20 newAsset = new MockERC20("New Test Token", "TEST", 18);
        MockERC4626 newVault = new MockERC4626(ERC20(asset), "New Test Token Vault", "TEST");
        
        pool.configureAsset(newAsset, newVault, LendingPool.Configuration(0.6e18, 0));
        
        (uint256 lendFactor, uint256 borrowFactor) = pool.configurations(newAsset);

        assertEq(lendFactor, 0.6e18);
        assertEq(borrowFactor, 0);
        assertEq(pool.baseUnits(newAsset), 1e18);
        assertEq(address(pool.vaults(newAsset)), address(newVault));
    }

    function testUpdateConfiguration() public {
        pool.updateConfiguration(asset, LendingPool.Configuration(0.9e18, 0)); 
        
        (uint256 lendFactor,) = pool.configurations(asset);

        assertEq(lendFactor, 0.9e18);
    }
    
    /*///////////////////////////////////////////////////////////////
                    ASSET CONFIGURATION SANITY CHECKS
    //////////////////////////////////////////////////////////////*/

    function testFailNewAssetConfigurationNotOwner() public {
        MockERC20 newAsset = new MockERC20("New Test Token", "TEST", 18);
        MockERC4626 newVault = new MockERC4626(ERC20(asset), "New Test Token Vault", "TEST");
    
        hevm.prank(address(0xBABE));
        pool.configureAsset(newAsset, newVault, LendingPool.Configuration(0.6e18, 0));
    }

    function testFailUpdateConfigurationNotOwner() public {
        hevm.prank(address(0xBABE));
        pool.updateConfiguration(asset, LendingPool.Configuration(0.9e18, 0)); 
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeposit(uint256 amount) public {
        hevm.assume(amount >= 1e5 && amount <= 1e27);

        // Mint, approve, and deposit the asset.
        mintAndApprove(asset, amount);
        pool.deposit(asset, amount, false);

        // Checks. Note that the default exchange rate is 1,
        // so the values should be equal to the input amount.
        assertEq(pool.balanceOf(asset, address(this)), amount, "Incorrect Balance");
        assertEq(pool.totalUnderlying(asset), amount, "Incorrect Total Underlying");
    }

    function testWithdrawal(uint256 amount) public {
        hevm.assume(amount >= 1e5 && amount <= 1e27);

        // Mint, approve, and deposit the asset.
        testDeposit(amount);

        // Withdraw the asset.
        pool.withdraw(asset, amount, false);

        // Checks.
        assertEq(asset.balanceOf(address(this)), amount, "Incorrect asset balance");
        assertEq(pool.balanceOf(asset, address(this)), 0, "Incorrect pool balance");
        assertEq(vault.balanceOf(address(pool)), 0, "Incorrect vault balance");
    }

    function testDepositEnableCollateral() public {
        // Mint, approve, and deposit the asset.
        mintAndApprove(asset, 1e18);
        pool.deposit(asset, 1e18, true);

        // Checks.
        assert(pool.enabledCollateral(address(this), asset));
    }

    function testWithdrawDisableCollateral() public {
        // Deposit and enable the asset as collateral.
        testDepositEnableCollateral();

        // Withdraw the asset and disable it as collateral.
        pool.withdraw(asset, 1e18, true);

        // Checks.
        assert(!pool.enabledCollateral(address(this), asset));
    }

    /*///////////////////////////////////////////////////////////////
                  DEPOSIT/WITHDRAWAL SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFailDepositAssetNotInPool() public {
        // Mock token.
        MockERC20 mockAsset = new MockERC20("Mock Token", "MKT", 18);
        
        // Mint tokens.
        mockAsset.mint(address(this), 1e18);

        // Approve the pool to spend half of the tokens.
        mockAsset.approve(address(pool), 0.5e18);

        // Attempt to deposit the tokens.
        pool.deposit(mockAsset, 1e18, false);
    }

    function testFailDepositWithNotEnoughApproval() public {
        // Mint tokens.
        asset.mint(address(this), 1e18);

        // Approve the pool to spend half of the tokens.
        asset.approve(address(pool), 0.5e18);

        // Attempt to deposit the tokens.
        pool.deposit(asset, 1e18, false);
    }
    
    function testFailWithdrawAssetNotInPool() public {
        // Mock token.
        MockERC20 mockAsset = new MockERC20("Mock Token", "MKT", 18);
        
        // Mint tokens.
        testDeposit(1e18);

        // Attempt to withdraw the tokens.
        pool.withdraw(mockAsset, 1e18, false);
    }

    function testFailWithdrawWithNotEnoughBalance() public {
        // Mint tokens.
        testDeposit(1e18);

        // Attempt to withdraw the tokens.
        pool.withdraw(asset, 2e18, false);
    }

    function testFailWithdrawWithNoBalance() public {
        // Attempt to withdraw tokens.
        pool.withdraw(asset, 1e18, false);
    }

    function testFailWithNoApproval() public {
        // Attempt to deposit tokens.
        pool.deposit(asset, 1e18, false);
    }

    /*///////////////////////////////////////////////////////////////
                         COLLATERALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testEnableCollateral() public {
        // Enable asset as collateral.
        pool.enableAsset(asset);

        // Checks.
        assertTrue(pool.enabledCollateral(address(this), asset));
    }

    function testDisableCollateral() external {
        // Enable the asset as collateral.
        testEnableCollateral();

        // Disable the asset as collateral.
        pool.disableAsset(asset);

        // Checks.
        assertFalse(pool.enabledCollateral(address(this), asset));
    }

    /*///////////////////////////////////////////////////////////////
                         BORROW/REPAYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testBorrow(uint256 amount) public {
        hevm.assume(amount >= 1e5 && amount <= 1e27);

        // Deposit tokens and enable them as collateral.
        mintAndApprove(asset, amount);
        pool.deposit(asset, amount, true);

        // Mint borrow tokens and supply them to the pool.
        mintAndApprove(borrowAsset, amount / 4);
        pool.deposit(borrowAsset, amount / 4, false);

        // Set the price of collateral to 1 ETH.
        oracle.updatePrice(asset, 1e18);

        // Set the price of the borrow asset to 2 ETH.
        // This means that with a 0.5 lend factor, we should be able to borrow 0.25 ETH.
        oracle.updatePrice(borrowAsset, 2e18);

        // Borrow the asset.
        pool.borrow(borrowAsset, amount / 4);

        // Checks.
        assertEq(borrowAsset.balanceOf(address(this)), amount / 4);
        assertEq(pool.borrowBalance(borrowAsset, address(this)), amount / 4);
        assertEq(pool.totalBorrows(borrowAsset), amount / 4);
        assertEq(pool.totalUnderlying(borrowAsset), amount / 4);
    }

    function testRepay(uint256 amount) public {
        hevm.assume(amount >= 1e5 && amount <= 1e27);

        // Borrow tokens.
        testBorrow(amount);

        // Repay the tokens.
        borrowAsset.approve(address(pool), amount / 4);
        pool.repay(borrowAsset, amount / 4);
    }

    function testInterestAccrual() public {
        uint256 amount = 1e18;

        // block number is 1.

        // Borrow tokens.
        testBorrow(amount);

        // Warp block number to 6.
        hevm.roll(block.number + 5);

        // Calculate the expected amount (after interest).
        // The borrow rate is constant, so the interest is always 5% per block.
        // expected = borrowed * interest ^ (blockDelta)
        uint256 expected = (amount / 4).mulWadDown(uint256(interestRateModel.getBorrowRate(0, 0, 0)).rpow(5, 1e18));

        // Checks.
        assertEq(pool.borrowBalance(borrowAsset, address(this)), expected);
        assertEq(pool.totalBorrows(borrowAsset), expected);
        assertEq(pool.totalUnderlying(borrowAsset), expected);
        assertEq(pool.balanceOf(borrowAsset, address(this)), expected);
    }

    /*///////////////////////////////////////////////////////////////
                   BORROW/REPAYMENT SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    function testFailBorrowAssetNotInPool() public {
        // Mock token.
        MockERC20 mockAsset = new MockERC20("Mock Token", "MKT", 18);
        
        // Amount to mint.
        uint256 amount = 1e18;

        // Deposit tokens and enable them as collateral.
        mintAndApprove(asset, amount);
        pool.deposit(asset, amount, true);

        // Mint borrow tokens and supply them to the pool.
        mintAndApprove(borrowAsset, amount / 4);
        pool.deposit(borrowAsset, amount / 4, false);

        // Set the price of collateral to 1 ETH.
        oracle.updatePrice(asset, 1e18);

        // Set the price of the borrow asset to 2 ETH.
        // This means that with a 0.5 lend factor, we should be able to borrow 0.25 ETH.
        oracle.updatePrice(borrowAsset, 2e18);

        // Borrow the asset.
        pool.borrow(mockAsset, amount / 4);
    }

    function testFailBorrowWithCollateralDisabled(uint256 amount) public {
        hevm.assume(amount >= 1e5 && amount <= 1e27);

        // Deposit tokens and enable them as collateral.
        mintAndApprove(asset, amount);
        pool.deposit(asset, amount, false);

        // Mint borrow tokens and supply them to the pool.
        mintAndApprove(borrowAsset, amount / 2);
        pool.deposit(borrowAsset, amount / 2, false);

        // Set the price of collateral to 1 ETH.
        oracle.updatePrice(asset, 1e18);

        // Set the price of the borrow asset to 2 ETH.
        // This means that with a 0.5 lend factor, we should be able to borrow 0.25 ETH.
        oracle.updatePrice(borrowAsset, 2e18);

        // Borrow the asset.
        pool.borrow(borrowAsset, amount / 4);
    }

    function testFailBorrowWithNoCollateral(uint256 amount) public {
        hevm.assume(amount >= 1e5 && amount <= 1e27);

        // Mint borrow tokens and supply them to the pool.
        mintAndApprove(borrowAsset, amount);
        pool.deposit(borrowAsset, amount, false);

        // Set the price of collateral to 1 ETH.
        oracle.updatePrice(asset, 1e18);

        // Set the price of the borrow asset to 2 ETH.
        // This means that with a 0.5 lend factor, we should be able to borrow 0.25 ETH.
        oracle.updatePrice(borrowAsset, 2e18);

        // Borrow the asset.
        pool.borrow(borrowAsset, amount);
    }

    function testFailBorrowWithNotEnoughCollateral(uint256 amount) public {
        hevm.assume(amount >= 1e5 && amount <= 1e27);

        // Deposit tokens and enable them as collateral.
        mintAndApprove(asset, amount);
        pool.deposit(asset, amount, true);

        // Mint borrow tokens and supply them to the pool.
        mintAndApprove(borrowAsset, amount / 2);
        pool.deposit(borrowAsset, amount / 2, false);

        // Set the price of collateral to 1 ETH.
        oracle.updatePrice(asset, 1e18);

        // Set the price of the borrow asset to 2 ETH.
        // This means that with a 0.5 lend factor, we should be able to borrow 0.25 ETH.
        oracle.updatePrice(borrowAsset, 2e18);

        // Borrow the asset.
        pool.borrow(borrowAsset, amount / 2);
    }

    function testCannotDisableIfBeingBorrowed() public {
        // Borrow asset.
        testBorrow(1e18);

        // Attempt to disable the asset as collateral.
        pool.disableAsset(borrowAsset);

        // Checks.
        assertTrue(pool.enabledCollateral(address(this), borrowAsset));
    }

    /*///////////////////////////////////////////////////////////////
                            FLASH LOAN TESTS
    //////////////////////////////////////////////////////////////*/

    function testFlashBorrow(uint256 amount) public {
        hevm.assume(amount >= 1e5 && amount <= 1e27);
        
        flashBorrower = new MockFlashBorrower();
        
        // Deposit tokens and enable them as collateral.
        mintAndApprove(asset, amount);
        pool.deposit(asset, amount, true);

        // Mint borrow tokens and supply them to the pool.
        mintAndApprove(borrowAsset, amount / 4);
        pool.deposit(borrowAsset, amount / 4, false);

        // Set the price of collateral to 1 ETH.
        oracle.updatePrice(asset, 1e18);

        // Set the price of the borrow asset to 2 ETH.
        // This means that with a 0.5 lend factor, we should be able to borrow 0.25 ETH.
        oracle.updatePrice(borrowAsset, 2e18);

        // Encode the address of the borrow asset
        bytes memory data = abi.encode(address(borrowAsset));

        // Approve pool to use 'amount' from flashBorrower
        hevm.startPrank(address(flashBorrower));
        borrowVault.approve(address(pool), amount);

        pool.flashBorrow(
            FlashBorrower(address(flashBorrower)),
            data,
            borrowAsset,
            amount / 4 
        );
    }

    /*///////////////////////////////////////////////////////////////
                      FLASH LOAN SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    // Cases where flash loans must not work.
    // - Not Enough Liquidity to flash borrow
    // - Ensure that a flash Borrow is not occuring
    function testFailFlashBorrowNotEnoughLiquidity(uint256 amount) public {
        hevm.assume(amount >= 1e5 && amount <= 1e27);
        
        flashBorrower = new MockFlashBorrower();
        
        // Deposit tokens and enable them as collateral.
        mintAndApprove(asset, amount);
        pool.deposit(asset, amount, true);

        // Mint borrow tokens and supply them to the pool.
        mintAndApprove(borrowAsset, amount / 4);
        pool.deposit(borrowAsset, amount / 4, false);

        // Set the price of collateral to 1 ETH.
        oracle.updatePrice(asset, 1e18);

        // Set the price of the borrow asset to 2 ETH.
        // This means that with a 0.5 lend factor, we should be able to borrow 0.25 ETH.
        oracle.updatePrice(borrowAsset, 2e18);

        // Encode the address of the borrow asset
        bytes memory data = abi.encode(address(borrowAsset));

        // Approve pool to use 'amount' from flashBorrower
        hevm.startPrank(address(flashBorrower));
        borrowVault.approve(address(pool), amount);

        pool.flashBorrow(
            FlashBorrower(address(flashBorrower)),
            data,
            borrowAsset,
            amount // Borrowing the full amount instead of amount/4
        );
    }

    function testFailFlashBorrowTwice(uint256 amount) public {
        hevm.assume(amount >= 1e5 && amount <= 1e27);
        
        flashBorrower2 = new MockFlashBorrower2();
        
        // Deposit tokens and enable them as collateral.
        mintAndApprove(asset, amount);
        pool.deposit(asset, amount, true);

        // Mint borrow tokens and supply them to the pool.
        mintAndApprove(borrowAsset, amount / 4);
        pool.deposit(borrowAsset, amount / 4, false);

        // Set the price of collateral to 1 ETH.
        oracle.updatePrice(asset, 1e18);

        // Set the price of the borrow asset to 2 ETH.
        // This means that with a 0.5 lend factor, we should be able to borrow 0.25 ETH.
        oracle.updatePrice(borrowAsset, 2e18);

        // Encode the address of the borrow asset
        bytes memory data = abi.encode(address(borrowAsset));

        // Approve pool to use 'amount' from flashBorrower
        hevm.startPrank(address(flashBorrower2));
        borrowVault.approve(address(pool), amount);

        // Flash borrow
        pool.flashBorrow(
            FlashBorrower(address(flashBorrower2)),
            data,
            borrowAsset,
            amount / 4 
        );
    }

    /*///////////////////////////////////////////////////////////////
                            LIQUIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testUserLiquidatable(uint256 amount) public {
        // TODO: do test with variable prices
        hevm.assume(amount >= 1e5 && amount <= 1e27);
        
        // Deposit tokens and enable them as collateral.
        mintAndApprove(asset, amount);
        pool.deposit(asset, amount, true);
        
        // Mint borrow tokens and supply them to the pool.
        mintAndApprove(borrowAsset, amount);
        pool.deposit(borrowAsset, amount, true);

        // Update borrow Asset configuration
        pool.updateConfiguration(borrowAsset, LendingPool.Configuration(0.5e18, 1e18)); 

        // Set the price of collateral.
        oracle.updatePrice(asset, 1e18);
        
        // Set the price of the borrow asset.
        oracle.updatePrice(borrowAsset, 1e18);

        // Borrow the maximum available of `borrowAsset`.
        pool.borrow(borrowAsset, pool.maxBorrowable());
        
        // Current Health factor should be 1.00.
        assertEq(pool.calculateHealthFactor(ERC20(address(0)), address(this), 0), 1e18);

        // drop the price of asset by 10%.
        oracle.updatePrice(asset, 0.9e18);
       
        // Assert User can be liquidated.
        assertTrue(pool.userLiquidatable(address(this)));
    }
    
    function testLiquidateUser() public {
        uint256 amount = 1e18;
       
        testUserLiquidatable(amount);

        uint256 health = pool.calculateHealthFactor(ERC20(address(0)), address(this), 0);

        uint256 repayAmount = liquidator.calculateRepayAmount(address(this), health);

        mintAndApprove(borrowAsset, repayAmount);
        pool.deposit(borrowAsset, repayAmount, true);

        assertEq(
            pool.calculateHealthFactor(ERC20(address(0)), address(this), 0), 
            pool.MAX_HEALTH_FACTOR()
        );
    }
    
    /*///////////////////////////////////////////////////////////////
                    LIQUIDATION SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    // Cases where liquidation must not work.

    /*///////////////////////////////////////////////////////////////
                        COLLATERALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testEnableAsset(uint256 amount) public {
        hevm.assume(amount >= 1e5 && amount <= 1e27);
        
        mintAndApprove(asset, amount);
        pool.deposit(asset, amount, false);

        pool.enableAsset(asset);

        assertTrue(pool.enabledCollateral(address(this), asset));
    }

    function testDisableAsset(uint256 amount) public {
        hevm.assume(amount >= 1e5 && amount <= 1e27);
        
        mintAndApprove(asset, amount);
        pool.deposit(asset, amount, true);

        pool.disableAsset(asset);

        assertFalse(pool.enabledCollateral(address(this), asset));
    }
    
    /*///////////////////////////////////////////////////////////////
                                 UTILS
    //////////////////////////////////////////////////////////////*/

    // Mint and approve assets.
    function mintAndApprove(MockERC20 underlying, uint256 amount) internal {
        underlying.mint(address(this), amount);
        underlying.approve(address(pool), amount);
    }
}
