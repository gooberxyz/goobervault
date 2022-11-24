// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./utils/BaseUnitTest.sol";

/// @dev Unit test suite for Accounting views behavior
contract AccountingUnitTestv2 is BaseUnitTest {
    //

    /*//////////////////////////////////////////////////////////////
    //
    // Feature: User checks reserves and balances of Goober
    //
    // As a Goober,
    // I want to check reserves and balances of Goober,
    // so that I can understand current liquidity, emissions, underlying value, and mint/hold balance.
    //
    // Acceptance Criteria:
    // - Should be able to check reserves like a vault with totalAssets()
    // - Should be able to check reserves like a pool with getReserves()
    // - Should be able to check how many GBR fractions would be minted for depositing
    //   a given amount of Goo and/or Mult
    // - Should be able to check how much Goo and Mult would be withdrawn for redeeming
    //   a given amount of GBR fractions
    // - Should be able to check Goo oracle price accumulator
    // - Should be able to check Mult oracle price accumulator
    //
    // Background: Starting balances and approvals (same for all unit tests)
    //
    // Given Alice, Bob, Carol, and Dave each have 2000 Goo
    // And Alice mints 3 Gobblers (mult9, mult8, mult6)
    // And Bob mints 1 Gobbler (mult9)
    // And Carol mints 2 Gobblers (mult6, mult7)
    // And Dave mints 0 Gobblers
    // And Alice, Bob, Carol, and Dave have approved Goober to spend their Goo and Gobblers
    // And Carol deposits 1000 Goo and 2 Gobblers (mult6, mult7) into Goober
    //
    //////////////////////////////////////////////////////////////*/

    function testTrue() public {
        assertTrue(true);
    }

    // TODO totalAssets

    // TODO getReserves

    // TODO checkConvertToAssets

    // TODO checkConvertToFractions

    // TODO gooPriceAccumulator // TWAP

    // TODO multPriceAccumulator // TWAP
}
