// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./utils/BaseUnitTest.sol";

/// @dev Unit test suite for Admin behavior
contract AdminUnitTestv2 is BaseUnitTest {
    //
    
    /*//////////////////////////////////////////////////////////////
    //
    // Feature: Protocol Admin administers Goober farm
    //
    // As the Protocol Admin,
    // we want to administer the Protocol,
    // so that we can maintain a healthy user ecosystem and sustainable farm economics.
    //
    // Acceptance Criteria:
    // - Protocol Admin should be able to flag/unflag a Gobbler, disallowing deposit
    // - Protocol Admin should be able to skim any misplaced ERC20 tokens to force balances to match reserves
    // - Protocol Admin should be able to sync to force reserves to match balances
    // - Protocol Admin should be able to set new Protocol Admin address
    // - Protocol Admin should be able to set new Minter address
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

    // TODO flag Gobbler

    // TODO unflag Gobbler

    // TODO skim

    // TODO sync

    // TODO setNewFeeTo

    // TODO setNewMinter
}
