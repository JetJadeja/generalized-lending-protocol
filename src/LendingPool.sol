// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {LendingPoolFactory} from "./LendingPoolFactory.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";

import {PriceOracle} from "./interface/PriceOracle.sol";
import {InterestRateModel} from "./interface/InterestRateModel.sol";
import {FlashBorrower} from "./interface/FlashBorrower.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/// @title Lending Pool
/// @author Jet Jadeja <jet@pentagon.xyz>
/// @notice Minimal, gas optimized lending pool contract
contract LendingPool is Auth {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;
    using FixedPointMathLib for uint256;

    /*///////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Pool name.
    string public name;

    /// @notice Create a new Lending Pool.
    /// @dev Retrieves the pool name from the LendingPoolFactory contract.
    constructor() Auth(Auth(msg.sender).owner(), Auth(msg.sender).authority()) {
        // Retrieve the name from the factory contract.
        name = LendingPoolFactory(msg.sender).poolDeploymentName();
    }

    /*///////////////////////////////////////////////////////////////
                          ORACLE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the price oracle contract.
    PriceOracle public oracle;

    /// @notice Emitted when the price oracle is changed.
    /// @param user The authorized user who triggered the change.
    /// @param newOracle The new price oracle address.
    event OracleUpdated(address indexed user, PriceOracle indexed newOracle);

    /// @notice Sets a new oracle contract.
    /// @param newOracle The address of the new oracle.
    function setOracle(PriceOracle newOracle) external requiresAuth {
        // Update the oracle.
        oracle = newOracle;

        // Emit the event.
        emit OracleUpdated(msg.sender, newOracle);
    }

    /*///////////////////////////////////////////////////////////////
                          IRM CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps ERC20 token addresses to their respective Interest Rate Model.
    mapping(ERC20 => InterestRateModel) public interestRateModels;

    /// @notice Emitted when an InterestRateModel is changed.
    /// @param user The authorized user who triggered the change.
    /// @param asset The underlying asset whose IRM was modified.
    /// @param newInterestRateModel The new IRM address.
    event InterestRateModelUpdated(address user, ERC20 asset, InterestRateModel newInterestRateModel);

    /// @notice Sets a new Interest Rate Model for a specfic asset.
    /// @param asset The underlying asset.
    /// @param newInterestRateModel The new IRM address.
    function setInterestRateModel(ERC20 asset, InterestRateModel newInterestRateModel) external requiresAuth {
        // Update the asset's Interest Rate Model.
        interestRateModels[asset] = newInterestRateModel;

        // Emit the event.
        emit InterestRateModelUpdated(msg.sender, asset, newInterestRateModel);
    }

    /*///////////////////////////////////////////////////////////////
                          ASSET CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps underlying tokens to the ERC4626 vaults where they are held.
    mapping(ERC20 => ERC4626) public vaults;

    /// @notice Maps underlying tokens to their configurations.
    mapping(ERC20 => Configuration) public configurations;

    /// @notice Maps underlying assets to their base units.
    /// 10**asset.decimals().
    mapping(ERC20 => uint256) public baseUnits;

    /// @notice Emitted when a new asset is added to the pool.
    /// @param user The authorized user who triggered the change.
    /// @param asset The underlying asset.
    /// @param vault The ERC4626 vault where the underlying tokens will be held.
    /// @param configuration The lend/borrow factors for the asset.
    event AssetConfigured(
        address indexed user,
        ERC20 indexed asset,
        ERC4626 indexed vault,
        Configuration configuration
    );

    /// @notice Emitted when an asset configuration is updated.
    /// @param user The authorized user who triggered the change.
    /// @param asset The underlying asset.
    /// @param newConfiguration The new lend/borrow factors for the asset.
    event AssetConfigurationUpdated(address indexed user, ERC20 indexed asset, Configuration newConfiguration);

    /// @dev Asset configuration struct.
    struct Configuration {
        uint256 lendFactor;
        uint256 borrowFactor;
    }

    /// @notice Adds a new asset to the pool.
    /// @param asset The underlying asset.
    /// @param vault The ERC4626 vault where the underlying tokens will be held.
    /// @param configuration The lend/borrow factors for the asset.
    function configureAsset(
        ERC20 asset,
        ERC4626 vault,
        Configuration memory configuration
    ) external requiresAuth {
        // Ensure that this asset has not been configured.
        require(address(vaults[asset]) == address(0), "ASSET_ALREADY_CONFIGURED");

        // Configure the asset.
        vaults[asset] = vault;
        configurations[asset] = configuration;
        baseUnits[asset] = 10**asset.decimals();

        // Emit the event.
        emit AssetConfigured(msg.sender, asset, vault, configuration);
    }

    /// @notice Updates the lend/borrow factors of an asset.
    /// @param asset The underlying asset.
    /// @param newConfiguration The new lend/borrow factors for the asset.
    function updateConfiguration(ERC20 asset, Configuration memory newConfiguration) external requiresAuth {
        // Update the asset configuration.
        configurations[asset] = newConfiguration;

        // Emit the event.
        emit AssetConfigurationUpdated(msg.sender, asset, newConfiguration);
    }

    /*///////////////////////////////////////////////////////////////
                       DEPOSIT/WITHDRAW INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a sucessful deposit.
    /// @param from The address that triggered the deposit.
    /// @param asset The underlying asset.
    /// @param amount The amount being deposited.
    event Deposit(address indexed from, ERC20 indexed asset, uint256 amount);

    /// @notice Emitted after a successful withdrawal.
    /// @param from The address that triggered the withdrawal.
    /// @param asset The underlying asset.
    /// @param amount The amount being withdrew.
    event Withdraw(address indexed from, ERC20 indexed asset, uint256 amount);

    /// @notice Deposit underlying tokens into the pool.
    /// @param asset The underlying asset.
    /// @param amount The amount to be deposited.
    /// @param enable A boolean indicating whether to enable the underlying asset as collateral.
    function deposit(
        ERC20 asset,
        uint256 amount,
        bool enable
    ) external {
        // Ensure the amount is valid.
        require(amount > 0, "INVALID_AMOUNT");

        // Calculate the amount of internal balance units to be stored.
        uint256 shares = amount.mulDivDown(baseUnits[asset], internalBalanceExchangeRate(asset));

        // Modify the internal balance of the sender.
        // Cannot overflow because the sum of all user
        // balances won't be greater than type(uint256).max
        unchecked {
            internalBalances[asset][msg.sender] += shares;
        }

        // Add to the asset's total internal supply.
        totalInternalBalances[asset] += shares;

        // Transfer underlying in from the user.
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // Deposit the underlying tokens into the designated vault.
        ERC4626 vault = vaults[asset];
        asset.approve(address(vault), amount);
        vault.deposit(amount, address(this));

        // If `enable` is set to true, enable the asset as collateral.
        if (enable) enableAsset(asset);

        // Emit the event.
        emit Deposit(msg.sender, asset, amount);
    }

    /// @notice Withdraw underlying tokens from the pool.
    /// @param asset The underlying asset.
    /// @param amount The amount to be withdrawn.
    /// @param disable A boolean indicating whether to disable the underlying asset as collateral.
    function withdraw(
        ERC20 asset,
        uint256 amount,
        bool disable
    ) external {
        // Ensure the amount is valid.
        require(amount > 0, "AMOUNT_TOO_LOW");

        // Calculate the amount of internal balance units to be subtracted.
        uint256 shares = amount.mulDivDown(baseUnits[asset], internalBalanceExchangeRate(asset));

        // Modify the internal balance of the sender.
        internalBalances[asset][msg.sender] -= shares;

        // Subtract from the asset's total internal supply.
        // Cannot undeflow because the user balance will 
        // never be greater than the total suuply. 
        unchecked {
            totalInternalBalances[asset] -= shares;
        }

        // Withdraw the underlying tokens from the designated vault.
        vaults[asset].withdraw(amount, address(this), address(this));

        // Transfer underlying to the user.
        asset.safeTransfer(msg.sender, amount);

        // If `disable` is set to true, disable the asset as collateral.
        if (disable) disableAsset(asset);

        // Emit the event.
        emit Withdraw(msg.sender, asset, amount);
    }

    /*///////////////////////////////////////////////////////////////
                      BORROW/REPAYMENT INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a successful borrow.
    /// @param from The address that triggered the borrow.
    /// @param asset The underlying asset.
    /// @param amount The amount being borrowed.
    event Borrow(address indexed from, ERC20 indexed asset, uint256 amount);

    /// @notice Emitted after a successful repayment.
    /// @param from The address that triggered the repayment.
    /// @param asset The underlying asset.
    /// @param amount The amount being repaid.
    event Repay(address indexed from, ERC20 indexed asset, uint256 amount);

    /// @notice Borrow underlying tokens from the pool.
    /// @param asset The underlying asset.
    /// @param amount The amount to borrow.
    function borrow(ERC20 asset, uint256 amount) external {
        // Ensure the amount is valid.
        require(amount > 0, "AMOUNT_TOO_LOW");

        // Accrue interest.
        // TODO: is this the right place to accrue interest?
        accrueInterest(asset);

        // Enable the asset, if it is not already enabled.
        enableAsset(asset);

        // Ensure the caller is able to execute this borrow.
        require(canBorrow(asset, msg.sender, amount));

        // Calculate the amount of internal debt units to be stored.
        uint256 debtUnits = amount.mulDivDown(baseUnits[asset], internalDebtExchangeRate(asset));

        // Update the internal borrow balance of the borrower.
        // Cannot overflow because the sum of all user
        // balances won't be greater than type(uint256).max
        unchecked {
            internalDebt[asset][msg.sender] += debtUnits;
        }

        // Add to the asset's total internal debt.
        totalInternalDebt[asset] += debtUnits;

        // Update the cached debt of the asset.
        cachedTotalBorrows[asset] += amount;

        // Transfer tokens to the borrower.
        vaults[asset].withdraw(amount, address(this), address(this));
        asset.transfer(msg.sender, amount);

        // Emit the event.
        emit Borrow(msg.sender, asset, amount);
    }

    /// @notice Repay underlying tokens to the pool.
    /// @param asset The underlying asset.
    /// @param amount The amount to repay.
    function repay(ERC20 asset, uint256 amount) public {
        // Ensure the amount is valid.
        require(amount > 0, "AMOUNT_TOO_LOW");

        // Calculate the amount of internal debt units to be stored.
        uint256 debtUnits = amount.mulDivDown(baseUnits[asset], internalDebtExchangeRate(asset));

        // Update the internal borrow balance of the borrower.
        internalDebt[asset][msg.sender] -= debtUnits;

        // Add to the asset's total internal debt.
        // Cannot undeflow because the user balance will 
        // never be greater than the total suuply.
        unchecked {
            totalInternalDebt[asset] -= debtUnits;
        }

        // Transfer tokens from the user.
        asset.safeTransferFrom(msg.sender, address(this), amount - 1);

        // Accrue interest.
        // TODO: is this the right place to accrue interest?
        accrueInterest(asset);

        // Emit the event.
        emit Repay(msg.sender, asset, amount);
    }

    /*///////////////////////////////////////////////////////////////
                          FLASH BORROW INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a successful flash borrow.
    /// @param from The address that triggered the flash borrow.
    /// @param borrower The borrower.
    event FlashBorrow(address indexed from, FlashBorrower indexed borrower, ERC20 indexed asset, uint256 amount);

    /// @notice Maps assets to the number of underlying being flash borrowed.
    mapping(ERC20 => uint256) flashBorrowed;

    /// @notice Execute a flash loan. This code will fail if the funds
    /// are not returned to the contract by the end of the transaction.
    /// @param borrower The address of the FlashBorrower contract to call.
    /// @param data The data to be passed to the FlashBorrower contract.
    /// @param asset The underlying asset.
    /// @param amount The amount to borrow.
    function flashBorrow(
        FlashBorrower borrower,
        bytes memory data,
        ERC20 asset,
        uint256 amount
    ) external {
        // Ensure that a flash borrow is not occuring in this asset.
        require(flashBorrowed[asset] == 0, "FLASH_BORROW_IN_PROGRESS");

        // Store the available liquidity before the borrow.
        uint256 liquidity = availableLiquidity(asset);

        // Withdraw the amount from the Vault and transfer it to the borrower.
        vaults[asset].withdraw(amount, address(borrower), address(this));

        // Update the flash borrow amount.
        flashBorrowed[asset] = amount;

        // Call the borrower.execute function.
        borrower.execute(amount, data);

        // Ensure the sufficient amount has been returned.
        ERC4626 vault = vaults[asset];
        require(vault.convertToAssets(vault.balanceOf(address(this))) + amount > liquidity, "AMOUNT_NOT_RETURNED");
        // Reset the flash borrow amount.
        delete flashBorrowed[asset];

        // Emit the event.
        emit FlashBorrow(msg.sender, borrower, asset, amount);
    }

    /*///////////////////////////////////////////////////////////////
                          LIQUIDATION INTERFACE
    //////////////////////////////////////////////////////////////*/

    // Maximum health factor after liquidation.
    uint256 public constant MAX_HEALTH_FACTOR = 1.25 * 1e18;

    function liquidateUser(
        ERC20 borrowedAsset,
        ERC20 collateralAsset, 
        address borrower,
        uint256 repayAmount
    ) external {
        require(userLiquidatable(borrower), "CANNOT_LIQUIDATE_HEALTHY_USER");

        // Calculate the number of collateral asset to be seized
        uint256 seizedCollateralAmount = seizeCollateral(borrowedAsset, collateralAsset, repayAmount);

        // Assert user health factor is == MAX_HEALTH_FACTOR
        require(calculateHealthFactor(borrowedAsset, borrower, 0) == MAX_HEALTH_FACTOR, "NOT_HEALTHY");
    }

    /// @dev Returns a boolean indicating whether a user is liquidatable.
    /// @param user The user to check.
    function userLiquidatable(address user) public view returns (bool) {
        // Call canBorrow(), passing in a non-existant asset and a borrow amount of 0.
        // This will just check the contract's current state.
        return !canBorrow(ERC20(address(0)), user, 0);
    }

    /// @dev Calculates the total amount of collateral tokens to be seized on liquidation.
    /// @param borrowedAsset The asset borrowed.
    /// @param collateralAsset The asset used as collateral.
    /// @param repayAmount The amount being repaid.
    function seizeCollateral(
        ERC20 borrowedAsset,
        ERC20 collateralAsset, 
        uint256 repayAmount
    ) public view returns (uint256) {
        return 0;
    }

    /*///////////////////////////////////////////////////////////////
                      COLLATERALIZATION INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after an asset has been collateralized.
    /// @param from The address that triggered the enablement.
    /// @param asset The underlying asset.
    event AssetEnabled(address indexed from, ERC20 indexed asset);

    /// @notice Emitted after an asset has been disabled.
    /// @param from The address that triggered the disablement.
    /// @param asset The underlying asset.
    event AssetDisabled(address indexed from, ERC20 indexed asset);

    /// @notice Maps users to an array of assets they have listed as collateral.
    mapping(address => ERC20[]) public userCollateral;

    /// @notice Maps users to a map from assets to boleans indicating whether they have listed as collateral.
    mapping(address => mapping(ERC20 => bool)) public enabledCollateral;

    /// @notice Enable an asset as collateral.
    function enableAsset(ERC20 asset) public {
        // Ensure the user has not enabled this asset as collateral.
        if (enabledCollateral[msg.sender][asset]) {
            return;
        }

        // Enable the asset as collateral.
        userCollateral[msg.sender].push(asset);
        enabledCollateral[msg.sender][asset] = true;

        // Emit the event.
        emit AssetEnabled(msg.sender, asset);
    }

    /// @notice Disable an asset as collateral.
    function disableAsset(ERC20 asset) public {
        // Ensure that the user is not borrowing this asset.
        if (internalDebt[asset][msg.sender] > 0) return;

        // Ensure the user has already enabled this asset as collateral.
        if (!enabledCollateral[msg.sender][asset]) return;

        // Remove the asset from the user's list of collateral.
        for (uint256 i = 0; i < userCollateral[msg.sender].length; i++) {
            if (userCollateral[msg.sender][i] == asset) {
                // Copy the value of the last element in the array.
                ERC20 last = userCollateral[msg.sender][userCollateral[msg.sender].length - 1];

                // Remove the last element from the array.
                delete userCollateral[msg.sender][userCollateral[msg.sender].length - 1];

                // Replace the disabled asset with the new asset.
                userCollateral[msg.sender][i] = last;
            }
        }

        // Disable the asset as collateral.
        enabledCollateral[msg.sender][asset] = false;

        // Emit the event.
        emit AssetDisabled(msg.sender, asset);
    }

    /*///////////////////////////////////////////////////////////////
                        LIQUIDITY ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the total amount of underlying tokens held by and owed to the pool.
    /// @param asset The underlying asset.
    function totalUnderlying(ERC20 asset) public view returns (uint256) {
        // Return the total amount of underlying tokens in the pool.
        // This includes the LendingPool's currently held assets and all of the assets being borrowed.
        return availableLiquidity(asset) + totalBorrows(asset) + flashBorrowed[asset];
    }

    /// @notice Returns the amount of underlying tokens held in this contract.
    /// @param asset The underlying asset.
    function availableLiquidity(ERC20 asset) public view returns (uint256) {
        // Return the LendingPool's underlying balance in the designated ERC4626 vault.
        ERC4626 vault = vaults[asset];
        return vault.convertToAssets(vault.balanceOf(address(this)));
    }

    /*///////////////////////////////////////////////////////////////
                        BALANCE ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Maps assets to user addresses to their balances, which are not denominated in underlying.
    /// Instead, these values are denominated in internal balance units, which internally account
    /// for user balances, increasing in value as the LendingPool earns more interest.
    mapping(ERC20 => mapping(address => uint256)) internal internalBalances;

    /// @dev Maps assets to the total number of internal balance units "distributed" amongst lenders.
    mapping(ERC20 => uint256) internal totalInternalBalances;

    /// @notice Returns the underlying balance of an address.
    /// @param asset The underlying asset.
    /// @param user The user to get the underlying balance of.
    function balanceOf(ERC20 asset, address user) public view returns (uint256) {
        // Multiply the user's internal balance units by the internal exchange rate of the asset.
        return internalBalances[asset][user].mulDivDown(internalBalanceExchangeRate(asset), baseUnits[asset]);
    }

    /// @dev Returns the exchange rate between underlying tokens and internal balance units.
    /// In other words, this function returns the value of one internal balance unit, denominated in underlying.
    function internalBalanceExchangeRate(ERC20 asset) internal view returns (uint256) {
        // Retrieve the total internal balance supply.
        uint256 totalInternalBalance = totalInternalBalances[asset];

        // If it is 0, return an exchange rate of 1.
        if (totalInternalBalance == 0) return baseUnits[asset];

        // Otherwise, divide the total supplied underlying by the total internal balance units.
        return totalUnderlying(asset).mulDivDown(baseUnits[asset], totalInternalBalance);
    }

    /*///////////////////////////////////////////////////////////////
                          DEBT ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Maps assets to user addresses to their debt, which are not denominated in underlying.
    /// Instead, these values are denominated in internal debt units, which internally account
    /// for user debt, increasing in value as the LendingPool earns more interest.
    mapping(ERC20 => mapping(address => uint256)) internal internalDebt;

    /// @dev Maps assets to the total number of internal debt units "distributed" amongst borrowers.
    mapping(ERC20 => uint256) internal totalInternalDebt;

    /// @notice Returns the underlying borrow balance of an address.
    /// @param asset The underlying asset.
    /// @param user The user to get the underlying borrow balance of.
    function borrowBalance(ERC20 asset, address user) public view returns (uint256) {
        // Multiply the user's internal debt units by the internal debt exchange rate of the asset.
        return internalDebt[asset][user].mulDivDown(internalDebtExchangeRate(asset), baseUnits[asset]);
    }

    /// @dev Returns the exchange rate between underlying tokens and internal debt units.
    /// In other words, this function returns the value of one internal debt unit, denominated in underlying.
    function internalDebtExchangeRate(ERC20 asset) internal view returns (uint256) {
        // Retrieve the total debt balance supply.
        uint256 totalInternalDebtUnits = totalInternalDebt[asset];

        // If it is 0, return an exchange rate of 1.
        if (totalInternalDebtUnits == 0) return baseUnits[asset];

        // Otherwise, divide the total borrowed underlying by the total amount of internal debt units.
        return totalBorrows(asset).mulDivDown(baseUnits[asset], totalInternalDebtUnits);
    }

    /*///////////////////////////////////////////////////////////////
                        INTEREST ACCRUAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Maps assets to the total number of underlying loaned out to borrowers.
    /// Note that these values are not updated, instead recording the total borrow amount
    /// each time a borrow/repayment occurs.
    mapping(ERC20 => uint256) internal cachedTotalBorrows;

    /// @dev Store the block number of the last interest accrual for each asset.
    mapping(ERC20 => uint256) internal lastInterestAccrual;

    /// @notice Returns the total amount of underlying tokens being loaned out to borrowers.
    /// @param asset The underlying asset.
    function totalBorrows(ERC20 asset) public view returns (uint256) {
        // Retrieve the Interest Rate Model for this asset.
        InterestRateModel interestRateModel = interestRateModels[asset];

        // Ensure the IRM has been set.
        require(address(interestRateModel) != address(0), "INTEREST_RATE_MODEL_NOT_SET");

        // Calculate the LendingPool's current underlying balance.
        // We cannot use totalUnderlying() here, as it calls this function,
        // leading to an infinite loop.
        uint256 underlying = availableLiquidity(asset) + cachedTotalBorrows[asset] + flashBorrowed[asset];

        // Retrieve the per-block interest rate from the IRM.
        uint256 interestRate = interestRateModel.getBorrowRate(underlying, cachedTotalBorrows[asset], 0);

        // Calculate the block number delta between the last accrual and the current block.
        uint256 blockDelta = block.number - lastInterestAccrual[asset];

        // If the delta is equal to the block number (a borrow/repayment has never occured)
        // return a value of 0.
        if (blockDelta == block.number) return cachedTotalBorrows[asset];

        // Calculate the interest accumulator.
        uint256 interestAccumulator = interestRate.rpow(blockDelta, 1e18);

        // Accrue interest.
        return cachedTotalBorrows[asset].mulWadDown(interestAccumulator);
    }

    /// @dev Update the cached total borrow amount for a given asset.
    /// @param asset The underlying asset.
    function accrueInterest(ERC20 asset) internal {
        // Set the cachedTotalBorrows to the total borrow amount.
        cachedTotalBorrows[asset] = totalBorrows(asset);

        // Update the block number of the last interest accrual.
        lastInterestAccrual[asset] = block.number;
    }

    /*///////////////////////////////////////////////////////////////
                      BORROW ALLOWANCE CHECKS
    //////////////////////////////////////////////////////////////*/

    /// @dev Store account liquidity details whilst avoiding stack depth errors.
    struct AccountLiquidity {
        // A user's total borrow balance in ETH.
        uint256 borrowBalance;
        // A user's maximum borrowable value. If their borrowed value
        // reaches this point, they will get liquidated.
        uint256 maximumBorrowable;
        // A user's borrow balance in ETH multiplied by the average borrow factor.
        // TODO: need a better name for this
        uint256 borrowBalancesTimesBorrowFactors;
        // A user's actual borrowable value. If their borrowed value
        // is greater than or equal to this number, the system will
        // not allow them to borrow any more assets.
        uint256 actualBorrowable;
    }

    /// @dev Calculate the health factor of a user after a borrow occurs.
    /// @param asset The underlying asset.
    /// @param user The user to check.
    /// @param amount The amount of underlying to borrow.
    function calculateHealthFactor(
        ERC20 asset,
        address user,
        uint256 amount
    ) public view returns (uint256) {
        // Allocate memory to store the user's account liquidity.
        AccountLiquidity memory liquidity;

        // Retrieve the user's utilized assets.
        ERC20[] memory utilized = userCollateral[user];
       
        // User's hyptothetical borrow balance.
        uint256 hypotheticalBorrowBalance;

        ERC20 currentAsset;

        // Iterate through the user's utilized assets.
        for (uint256 i = 0; i < utilized.length; i++) {
            
            // Current user utilized asset.
            currentAsset = utilized[i];
            
            // Calculate the user's maximum borrowable value for this asset.
            // balanceOfUnderlying(asset,user) * ethPrice * collateralFactor.
            liquidity.maximumBorrowable += balanceOf(currentAsset, user)
                .mulDivDown(oracle.getUnderlyingPrice(currentAsset), baseUnits[currentAsset])
                .mulDivDown(configurations[currentAsset].lendFactor, 1e18);

            // Check if current asset == underlying asset.
            hypotheticalBorrowBalance = currentAsset == asset ? amount : 0;
            
            // Calculate the user's hypothetical borrow balance for this asset.
            if (internalDebt[currentAsset][msg.sender] > 0) {
                hypotheticalBorrowBalance += borrowBalance(currentAsset, user);
            }

            // Add the user's borrow balance in this asset to their total borrow balance.
            liquidity.borrowBalance += hypotheticalBorrowBalance.mulDivDown(
                oracle.getUnderlyingPrice(currentAsset),
                baseUnits[currentAsset]
            );

            // Multiply the user's borrow balance in this asset by the borrow factor.
            liquidity.borrowBalancesTimesBorrowFactors += hypotheticalBorrowBalance
                .mulDivDown(oracle.getUnderlyingPrice(currentAsset), baseUnits[currentAsset])
                .mulWadDown(configurations[currentAsset].borrowFactor);
        }

        // Calculate the user's actual borrowable value.
        uint256 actualBorrowable = liquidity
            .borrowBalancesTimesBorrowFactors
            .divWadDown(liquidity.borrowBalance)
            .mulWadDown(liquidity.maximumBorrowable);

        // Return whether the user's hypothetical borrow value is
        // less than or equal to their borrowable value.
        return actualBorrowable.divWadDown(liquidity.borrowBalance);
    }

    /// @dev Identify whether a user is able to execute a borrow.
    /// @param asset The underlying asset.
    /// @param user The user to check.
    /// @param amount The amount of underlying to borrow.
    function canBorrow(
        ERC20 asset,
        address user,
        uint256 amount
    ) internal view returns (bool) {
        // Ensure the user's health factor will be greater than 1.
        return calculateHealthFactor(asset, user, amount) >= 1e18;
    }

    /// @dev Given user's collaterals, calculate the maximum user can borrow.
    function maxBorrowable() external returns (uint256 maximumBorrowable) {
        // Retrieve the user's utilized assets.
        ERC20[] memory utilized = userCollateral[msg.sender];

        ERC20 currentAsset;

        // Iterate through the user's utilized assets.
        for (uint256 i = 0; i < utilized.length; i++) {

            // Current user utilized asset.
            currentAsset = utilized[i];

            // Calculate the user's maximum borrowable value for this asset.
            // balanceOfUnderlying(asset,user) * ethPrice * lendFactor.
            maximumBorrowable += balanceOf(currentAsset, msg.sender)
                .mulDivDown(oracle.getUnderlyingPrice(currentAsset), baseUnits[currentAsset])
                .mulDivDown(configurations[currentAsset].lendFactor, 1e18);
        }
    }

    /// @dev Get all user collateral assets.
    /// @param user The user.
    function getCollateral(address user) external returns (ERC20[] memory) {
        return userCollateral[user];
    }
}
