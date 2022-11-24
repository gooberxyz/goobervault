// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./utils/BaseUnitTest.sol";

/// @dev Unit test suite for Deposit behavior
contract DepositUnitTestv2 is BaseUnitTest {
    //

    /*//////////////////////////////////////////////////////////////
    //
    // Feature: User deposits into Goober
    //
    // As a Goober,
    // I want to deposit my Goo and/or Gobblers with my fellow Goober community,
    // so that we produce more Goo emissions together than we would on our own.
    //
    // Acceptance Criteria:
    // - Should be able to preview deposit
    // - Should be able to deposit Goo and/or Gobblers in exchange for minting GBR vault fractions
    // - Should be able to safe deposit, which ensures a deadline after which the tx will revert, 
    //   and minimum amount of GBR fractions to be minted
    // - K Accounting: TODO
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

    /*//////////////////////////////////////////////////////////////
    //
    // Scenario: Preview deposit
    //
    // When Alice previews a deposit of 500 Goo and 1 Gobbler mult9
    // Then Alice should see TODO GBR as the amount of fractions to be minted
    //
    */

    function testPreviewDeposit() public {
        gobblersOne = [1]; // tokenID 1

        vm.prank(alice);
        uint256 fractionsToMint = goober.previewDeposit(gobblersOne, 500 ether);

        assertEq(fractionsToMint, 66288649161279999462);
    }

    // TODO sad paths

    /*//////////////////////////////////////////////////////////////
    //
    // Scenario: Deposit Goo and Gobblers
    //
    // When Alice deposits 500 Goo and 1 Gobbler mult9
    // Then Alice should mint TODO GBR fractions
    //
    */

    function testDeposit() public {
        gobblersOne = [1];

        vm.startPrank(alice);
        uint256 expected = goober.previewDeposit(gobblersOne, 500 ether);
        uint256 fractionsMinted = goober.deposit(gobblersOne, 500 ether, alice);
        vm.stopPrank();

        assertEq(fractionsMinted, expected);

        // TODO add assertion helpers
        /*
        assertUserBalances()
            - User fractions
            - User Goo balance
            - User Gobbler ownership
            - User Mult

        assertVaultAccounting()
            - Vault total fractions
            - Vault Gobbler ownership
            - Vault Goo balance from totalAssets()
            - Vault Mult from totalAssets()
            - Vault Goo balance from totalAssets()
            - Vault Mult from totalAssets()
            - Vault last liquidity event timestamp from totalAssets()
        
        assertK()
            - Delta K
            - kLast
            - kDebt
        
        assertFees()
            - Liquidity Fee via Vault
            - Liquidity Fee via User
            - Liquidity Fee via FeeTo
            - Performance Fee via Vault
            - Performance Fee via User
            - Performance Fee via FeeTo
        
        assertAccumulators()
            - Goo cumulative price
            - Mult cumulative price
        */
    }

    // TODO just Goo, just Gobblers
    // TODO sad paths

    /*//////////////////////////////////////////////////////////////
    //
    // Scenario: Safe deposit Goo
    //
    // When Alice safe deposits 500 Goo and 1 Gobbler mult9, with TODO min fractions and TODO deadline
    // Then Alice should mint TODO GBR fractions
    //
    */

    function testSafeDeposit() public {
        gobblersOne = [1];

        vm.startPrank(alice);
        uint256 expected = goober.previewDeposit(gobblersOne, 500 ether);
        uint256 fractionsMinted = goober.safeDeposit(gobblersOne, 500 ether, alice, expected, block.timestamp);
        vm.stopPrank();

        assertEq(fractionsMinted, expected);
    }

    // TODO just Goo, just Gobblers
    // TODO with other receiver
    // TODO sad paths
}
