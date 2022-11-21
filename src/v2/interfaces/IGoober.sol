// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IGoober {
    //

    /*//////////////////////////////////////////////////////////////
    //  Events
    //////////////////////////////////////////////////////////////*/

    // Deposit and Withdraw
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

    // Swap
    event Swap(
        address indexed caller,
        address indexed receiver,
        uint256 gooTokensIn,
        uint256 gobblersMultIn,
        uint256 gooTokensOut,
        uint256 gobblerMultOut
    );

    // Accounting and Fees
    event FeesAccrued(address indexed feeTo, uint256 fractions, bool performanceFee, uint256 _deltaK);
    event Sync(uint256 gooBalance, uint256 multBalance);

    /*//////////////////////////////////////////////////////////////
    //  Errors
    //////////////////////////////////////////////////////////////*/

    // Balance Errors
    error InsufficientAllowance();
    error InsufficientGoo(uint256 amount, uint256 actualK, uint256 expectedK);

    // Deposit and Withdraw
    error InsufficientLiquidityDeposited();
    error InsufficientLiquidityWithdrawn();
    error BurnAboveLimit();

    // Swap
    error InsufficientInputAmount(uint256 amount0In, uint256 amount1In);
    error InsufficientOutputAmount(uint256 gooOut, uint256 gobblersOut);
    error InvalidReceiver(address receiver);
    error ExcessiveErroneousGoo(uint256 actualErroneousGoo, uint256 allowedErroneousGoo);

    // K Calculation Errors
    error MustLeaveLiquidity(uint256 gooBalance, uint256 gobblerBalance);

    // Time Errors
    error Expired(uint256 time, uint256 deadline);

    error MintBelowLimit();

    // NFT Errors
    error InvalidNFT();
    error InvalidMultiplier(uint256 gobblerId);

    /*//////////////////////////////////////////////////////////////
    //  Accounting
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
    //  DEPOSIT
    //////////////////////////////////////////////////////////////*/

    /// @notice Previews a deposit of the supplied Gobblers and Goo.
    /// @param gobblers - Array of Gobbler ids.
    /// @param gooTokens - Amount of Goo to deposit.
    /// @return fractions - Amount of fractions created.
    function previewDeposit(uint256[] calldata gobblers, uint256 gooTokens) external view returns (uint256 fractions);

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

    /*//////////////////////////////////////////////////////////////
    //  WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @notice Previews a withdraw of the requested Gobblers and Goo tokens from the vault.
    /// @param gobblers - Array of Gobbler ids.
    /// @param gooTokens - Amount of Goo to withdraw.
    /// @return fractions - Amount of fractions withdrawn.
    function previewWithdraw(uint256[] calldata gobblers, uint256 gooTokens)
        external
        view
        returns (uint256 fractions);

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

    /*//////////////////////////////////////////////////////////////
    //  SWAP
    //////////////////////////////////////////////////////////////*/

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
