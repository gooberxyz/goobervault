// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "./IERC20Metadata.sol";
import "./IERC721Receiver.sol";

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
     * @notice The caller doesn't have permission to access the function.
     * @param accessor The requesting address.
     * @param permissioned The address which has the requisite permissions.
     */
    error AccessControlViolation(address accessor, address permissioned);

    /**
     * @notice Invalid feeTo address.
     * @param feeTo the feeTo address.
     */
    error InvalidAddress(address feeTo);

    // Structs

    /// @dev Intermediary struct for swap calculation.
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

    /// @return gooTokens The total amount of Goo owned.
    /// @return gobblerMult The total multiple of all Gobblers owned.
    function totalAssets() external view returns (uint256 gooTokens, uint256 gobblerMult);

    /// @param gooTokens - The amount of Goo to simulate.
    /// @param gobblerMult - The amount of Gobbler mult in to simulate.
    /// @return fractions - The fractions, without any fees assessed, which would be returned for a deposit.
    function convertToFractions(uint256 gooTokens, uint256 gobblerMult) external view returns (uint256 fractions);

    /// @param fractions The amount of fractions to simulate converting.
    /// @param gooTokens - The amount of Goo out.
    /// @param gobblerMult - The amount of Gobbler mult out.
    function convertToAssets(uint256 fractions) external view returns (uint256 gooTokens, uint256 gobblerMult);

    /// @notice Gets the vault reserves of Goo and Gobbler mult, along with the last update time.
    /// @dev This can be used to calculate slippage on a swap of certain sizes
    /// @dev using Uni V2 style liquidity math.
    /// @return _gooReserve - The amount of Goo in the tank for the pool.
    /// @return _gobblerReserve - The total multiplier of all Gobblers in the pool.
    /// @return _blockTimestampLast - The last time that the oracles were updated.
    function getReserves()
        external
        view
        returns (uint256 _gooReserve, uint256 _gobblerReserve, uint32 _blockTimestampLast);

    /// @notice Previews a deposit of the supplied Gobblers and Goo.
    /// @param gobblers - Array of Gobbler ids.
    /// @param gooTokens - Amount of Goo to deposit.
    /// @return fractions - Amount of fractions created.
    function previewDeposit(uint256[] calldata gobblers, uint256 gooTokens) external view returns (uint256 fractions);

    /// @notice Previews a withdraw of the requested Gobblers and Goo tokens from the vault.
    /// @param gobblers - Array of Gobbler ids.
    /// @param gooTokens - Amount of Goo to withdraw.
    /// @return fractions - Amount of fractions withdrawn.
    function previewWithdraw(uint256[] calldata gobblers, uint256 gooTokens)
        external
        view
        returns (uint256 fractions);

    /// @notice Simulates a swap.
    /// @param gobblersIn - Array of Gobbler ids to swap in.
    /// @param gooIn - Amount of Goo to swap in.
    /// @param gobblersOut - Array of Gobbler ids to swap out.
    /// @param gooOut - Amount of Goo to swap out.
    /// @return erroneousGoo - The amount in wei by which to increase or decrease gooIn/Out to balance the swap.
    function previewSwap(uint256[] calldata gobblersIn, uint256 gooIn, uint256[] calldata gobblersOut, uint256 gooOut)
        external
        view
        returns (int256 erroneousGoo);

    /*//////////////////////////////////////////////////////////////
    // External: Mutating, Restricted Access
    //////////////////////////////////////////////////////////////*/

    // Access Control

    /**
     * @notice Updates the address that fees are sent to.
     * @param newFeeTo The new address to which fees will be sent.
     */
    function setFeeTo(address newFeeTo) external;

    /**
     * @notice Updates the address that can call mintGobbler.
     * @param newMinter The new address to which will be able to call mintGobbler.
     */
    function setMinter(address newMinter) external;

    // Other Privileged Functions

    /// @notice Mints Gobblers using the pool's virtual reserves of Goo
    /// @notice when specific conditions are met.
    function mintGobbler() external;

    /// @notice Restricted function for skimming any ERC20s that may have been erroneously sent to the pool.
    function skim(address erc20) external;

    /// @notice Restricted function for blocking/unblocking compromised Gobblers from the pool.
    function flagGobbler(uint256 tokenId, bool _flagged) external;

    /*//////////////////////////////////////////////////////////////
    // External: Mutating, Unrestricted
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits the supplied Gobblers/Goo from the owner and sends fractions to the receiver.
    /// @param gobblers - Array of Gobbler ids.
    /// @param gooTokens - Amount of Goo to deposit.
    /// @param receiver - Address to receive fractions.
    /// @return fractions - Amount of fractions created.
    function deposit(uint256[] calldata gobblers, uint256 gooTokens, address receiver)
        external
        returns (uint256 fractions);

    /// @notice Deposits the supplied Gobblers/Goo from the owner and sends fractions to the
    /// @notice receiver whilst ensuring a deadline is met, and a minimum amount of fractions are created.
    /// @param gobblers - Array of Gobbler ids to deposit.
    /// @param gooTokens - Amount of Goo to deposit.
    /// @param receiver - Address to receive fractions.
    /// @param minFractionsOut - Minimum amount of fractions to be sent.
    /// @param deadline - Unix timestamp by which the transaction must execute.
    /// @return fractions - Amount of fractions created.
    function safeDeposit(
        uint256[] calldata gobblers,
        uint256 gooTokens,
        address receiver,
        uint256 minFractionsOut,
        uint256 deadline
    ) external returns (uint256 fractions);

    /// @notice Withdraws the requested Gobblers and Goo from the vault.
    /// @param gobblers - Array of Gobbler ids to withdraw
    /// @param gooTokens - Amount of Goo to withdraw.
    /// @param receiver - Address to receive the Goo and Gobblers.
    /// @param owner - Owner of the fractions to be destroyed.
    /// @return fractions - Amount of fractions destroyed.
    function withdraw(uint256[] calldata gobblers, uint256 gooTokens, address receiver, address owner)
        external
        returns (uint256 fractions);

    /// @notice Withdraws the requested Gobblers/Goo from the vault to the receiver and destroys fractions
    /// @notice from the owner whilst ensuring a deadline is met, and a maximimum amount of fractions are destroyed.
    /// @param gobblers - Array of Gobbler ids to withdraw.
    /// @param gooTokens - Amount of Goo to withdraw.
    /// @param receiver - Address to receive the Goo and Gobblers.
    /// @param owner - Owner of the fractions to be destroyed.
    /// @param maxFractionsIn - Maximum amount of fractions to be destroyed.
    /// @param deadline - Unix timestamp by which the transaction must execute.
    /// @return fractions - Aamount of fractions destroyed.
    function safeWithdraw(
        uint256[] calldata gobblers,
        uint256 gooTokens,
        address receiver,
        address owner,
        uint256 maxFractionsIn,
        uint256 deadline
    ) external returns (uint256 fractions);

    /// @notice Swaps supplied Gobblers/Goo for Gobblers/Goo in the pool.
    function swap(
        uint256[] calldata gobblersIn,
        uint256 gooIn,
        uint256[] calldata gobblersOut,
        uint256 gooOut,
        address receiver,
        bytes calldata data
    ) external returns (int256 erroneousGoo);

    /// @notice Swaps supplied Gobblers/Goo for Gobblers/Goo in the pool, with slippage and deadline control.
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
