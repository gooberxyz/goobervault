// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IGoober {
    //

    /*//////////////////////////////////////////////////////////////
    //  Events
    //////////////////////////////////////////////////////////////*/

    //

    /*//////////////////////////////////////////////////////////////
    //  Errors
    //////////////////////////////////////////////////////////////*/

    // Deposit Errors
    error InsufficientLiquidityDeposited();

    // K Calculation Errors
    error MustLeaveLiquidity(uint256 gooBalance, uint256 gobblerBalance);

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
    //  Deposit
    //////////////////////////////////////////////////////////////*/

    /// @notice Previews a deposit of the supplied Gobblers and Goo.
    /// @param gobblers - Array of Gobbler ids.
    /// @param gooTokens - Amount of Goo to deposit.
    /// @return fractions - Amount of fractions created.
    function previewDeposit(uint256[] calldata gobblers, uint256 gooTokens) external view returns (uint256 fractions);
}
