// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "./IERC20Metadata.sol";
import "./IERC721Receiver.sol";

// Would be nice to inherit from IERC20 here.
interface IGoober is IERC721Receiver {
    // Errors

    // Balance Errors
    error InsufficientAllowance();
    error InsufficientGoo(uint256 amount, uint256 actualK, uint256 expectedK);

    // Deposit Errors
    error InsufficientLiquidityDeposited();
    error MintBelowLimit();

    // K Calculation Errors
    error MustLeaveLiquidity(uint256 gooBalance, uint256 gobblerBalance);

    // Mint Errors
    error AuctionPriceTooHigh(uint256 auctionPrice, uint256 poolPrice);
    error InsufficientLiquidity(uint256 gooBalance, uint256 gobblerBalance);
    error MintFailed();

    // NFT Errors
    error InvalidNFT();
    error InvalidMultiplier(uint256 gobblerId);

    // Skim Errors
    error NoSkim();

    // Swap Errors
    error InsufficientInputAmount(uint256 amount0In, uint256 amount1In);
    error InsufficientOutputAmount(uint256 gooOut, uint256 gobblersOut);
    error InvalidReceiver(address receiver);
    error ExcessiveErroneousGoo(uint256 actualErroneousGoo, uint256 allowedErroneousGoo);

    // Time Errors
    error Expired(uint256 time, uint256 deadline);

    // Withdraw Errors
    error InsufficientLiquidityWithdrawn();
    error BurnAboveLimit();

    /**
     * @notice The caller doesn't have permission to access that function.
     * @param accessor The requesting address.
     * @param permissioned The address which has the requisite permissions.
     */
    error AccessControlViolation(address accessor, address permissioned);

    /**
     * @notice Invalid fee to address.
     * @param feeTo the feeTo address.
     */
    error InvalidAddress(address feeTo);

    // Structs

    struct SwapData {
        uint256 gooReserve;
        uint256 gobblerReserve;
        uint256 gooBalance;
        uint256 gobblerBalance;
        uint256 multOut;
        uint256 amount0In;
        uint256 amount1In;
        int256 erroneousGoo;
    }

    // Events

    event VaultMint(address indexed minter, uint256 auctionPricePerMult, uint256 poolPricePerMult, uint256 gooConsumed);

    event Deposit(
        address indexed caller, address indexed receiver, uint256[] gobblers, uint256 gooTokens, uint256 fractions
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256[] gobblers,
        uint256 gooTokens,
        uint256 fractions
    );

    event FeesAccrued(address indexed feeTo, uint256 fractions, bool performanceFee, uint256 _deltaK);

    event Swap(
        address indexed caller,
        address indexed receiver,
        uint256 gooTokensIn,
        uint256 gobblersMultIn,
        uint256 gooTokensOut,
        uint256 gobblerMultOut
    );

    event Sync(uint256 gooBalance, uint256 multBalance);

    /*//////////////////////////////////////////////////////////////
    // External: Non Mutating
    //////////////////////////////////////////////////////////////*/

    /// @return gooTokens the total amount of goo owned
    /// @return gobblerMult the total multiple of all gobblers owned
    function totalAssets() external view returns (uint256 gooTokens, uint256 gobblerMult);

    // @param gooTokens the token amount to simulate.
    // @param gobblerMult - the multiplier amount of gobblers in to simulate.
    // @return fractions - the fraction without any fees assessed which would be returned for a deposit.
    function convertToFractions(uint256 gooTokens, uint256 gobblerMult) external view returns (uint256 fractions);

    // @param fractions the amount of fractions to simulate converting.
    // @param gooTokens - the token amount out.
    // @param gobblerMult - the multiplier amount of gobblers out.
    function convertToAssets(uint256 fractions) external view returns (uint256 gooTokens, uint256 gobblerMult);

    /// @notice get the vault reserves of goo and gobbler multiplier, along with the last update time
    /// @dev This can be used to calculate slippage on a swap of certain sizes
    ///      using uni-v2 style liquidity math.
    /// @return _gooReserve - the total amount of goo in the tank for all owned gobblers
    /// @return _gobblerReserve - the total multiplier of all gobblers owned
    /// @return _blockTimestampLast - the last time that the reserves were updated
    function getReserves()
        external
        view
        returns (uint256 _gooReserve, uint256 _gobblerReserve, uint32 _blockTimestampLast);

    /// @notice Previews a deposit of the supplied gobblers and goo.
    /// @param gobblers - array of gobbler ids
    /// @param gooTokens - amount of goo to deposit
    /// @return fractions - amount of GBR minted
    function previewDeposit(uint256[] calldata gobblers, uint256 gooTokens) external view returns (uint256 fractions);

    /// @notice Previews a withdraw of the requested gobblers and goo tokens from the vault.
    /// @param gobblers - array of gobbler ids.
    /// @param gooTokens - amount of goo to withdraw.
    /// @return fractions - amount of fractions that have been withdrawn.
    function previewWithdraw(uint256[] calldata gobblers, uint256 gooTokens)
        external
        view
        returns (uint256 fractions);

    /// @notice Simulates a swap.
    /// @param gobblersIn - array of gobbler ids to swap in.
    /// @param gooIn - amount of goo to swap in.
    /// @param gobblersOut - array of gobbler ids to swap out.
    /// @param gooOut - amount of goo to swap out.
    /// @return erroneousGoo - the amount in wei by which to increase or decreas gooIn/out to balance the swap.
    function previewSwap(uint256[] calldata gobblersIn, uint256 gooIn, uint256[] calldata gobblersOut, uint256 gooOut)
        external
        view
        returns (int256 erroneousGoo);

    /*//////////////////////////////////////////////////////////////
    // External: Mutating, Admin
    //////////////////////////////////////////////////////////////*/

    // Access Control

    /**
     * @notice Updates the address fees can be swept to.
     * @param newFeeTo The new address to which fees will be swept.
     */
    function setFeeTo(address newFeeTo) external;

    /**
     * @notice Updates the address fees can be swept to.
     * @param newMinter The new address to which fees will be swept.
     */
    function setMinter(address newMinter) external;

    // Other Privileged Functions

    /// @notice Mints as many Gobblers as possible using the vault's.
    /// @notice virtual reserves of Goo, if specific curve balancing conditions.
    /// @notice are met and the vault can afford to mint.
    function mintGobbler() external;

    /// @notice Admin function for skimming any ERC20 that may have been sent in error.
    function skim(address erc20) external;

    /*//////////////////////////////////////////////////////////////
    // External: Mutating, Unrestricted
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits the supplied gobblers/goo from the owner and mints GBR to the receiver.
    /// @param gobblers - array of gobbler ids.
    /// @param gooTokens - amount of goo to deposit.
    /// @param receiver - address to receive GBR.
    /// @return fractions - amount of GBR minted.
    function deposit(uint256[] calldata gobblers, uint256 gooTokens, address receiver)
        external
        returns (uint256 fractions);

    /// @notice Deposits the supplied gobblers/goo from the owner and mints GBR to the
    ///         receiver while ensuring a deadline and minimum amount of fractions were minted.
    /// @param gobblers - array of gobbler ids.
    /// @param gooTokens - amount of goo to withdraw.
    /// @param receiver - address to receive GBR.
    /// @param minFractionsOut - minimum amount of GBR to be minted.
    /// @param deadline - Unix timestamp after which the transaction will revert.
    /// @return fractions - amount of GBR minted.
    function safeDeposit(
        uint256[] calldata gobblers,
        uint256 gooTokens,
        address receiver,
        uint256 minFractionsOut,
        uint256 deadline
    ) external returns (uint256 fractions);

    /// @notice Withdraws the requested gobblers and goo tokens from the vault.
    /// @param gobblers - array of gobbler ids.
    /// @param gooTokens - amount of goo to withdraw.
    /// @param receiver - address to receive the goo and gobblers.
    /// @param owner - owner of the fractions to be withdrawn.
    /// @return fractions - amount of fractions that have been withdrawn.
    function withdraw(uint256[] calldata gobblers, uint256 gooTokens, address receiver, address owner)
        external
        returns (uint256 fractions);

    /// @notice Withdraws the requested gobblers and goo tokens from the vault.
    /// @param gobblers - array of gobbler ids.
    /// @param gooTokens - amount of goo to withdraw.
    /// @param receiver - address to receive the goo and gobblers.
    /// @param owner - owner of the fractions to be withdrawn.
    /// @param maxFractionsIn - maximum amount of GBR to be burned.
    /// @param deadline - Unix timestamp after which the transaction will revert.
    /// @return fractions - amount of fractions that have been withdrawn.
    function safeWithdraw(
        uint256[] calldata gobblers,
        uint256 gooTokens,
        address receiver,
        address owner,
        uint256 maxFractionsIn,
        uint256 deadline
    ) external returns (uint256 fractions);

    /// @notice Swaps supplied gobblers/goo for gobblers/goo in the pool.
    function swap(
        uint256[] calldata gobblersIn,
        uint256 gooIn,
        uint256[] calldata gobblersOut,
        uint256 gooOut,
        address receiver,
        bytes calldata data
    ) external returns (int256 erroneousGoo);

    /// @notice Swaps supplied gobblers/goo for gobblers/goo in the pool, with slippage and deadline control.
    function safeSwap(
        uint256 erroneousGooAbs,
        uint256 deadline,
        uint256[] calldata gobblersIn,
        uint256 gooIn,
        uint256[] calldata gobblersOut,
        uint256 gooOut,
        address receiver,
        bytes calldata data
    ) external returns (int256 erroneousGoo);
}
