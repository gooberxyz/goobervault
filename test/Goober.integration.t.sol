// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import "art-gobblers/Goo.sol";
import "art-gobblers/../test/utils/mocks/LinkToken.sol";
import "art-gobblers/../lib/chainlink/contracts/src/v0.8/mocks/VRFCoordinatorMock.sol";
import {ChainlinkV1RandProvider} from "art-gobblers/utils/rand/ChainlinkV1RandProvider.sol";
import {Utilities} from "art-gobblers/../test/utils/Utilities.sol";
import "art-gobblers/utils/GobblerReserve.sol";
import "./mocks/MockERC721.sol";

import "../src/Goober.sol";
import "../src/interfaces/IGoober.sol";

// TODO Spot check data table and fill in any outstanding XYZs
// TODO Improve tracking on aliceGooBalance, bobGooBalance, aliceGooberBalance, bobGooberBalance
// TODO Add numerical assertions for management and performance fees accruing to FeeTo account
// TODO Bring in LibGOO for actual emission amounts
// TODO Use previewDeposit, previewWithdraw, previewSwap for asserting actual results
// TODO Consider forking mainnet and running against deployed Goo / ArtGobblers contracts
// TODO Consider fuzzing # Gobblers to mint, Goo deposit amounts, Swap params, and time to let Goo accrue
// TODO Refactor test helpers into base class or test utility lib

contract GooberIntegrationTest is Test {
    using stdStorage for StdStorage;

    Goober internal goober;

    Utilities internal utils;

    ArtGobblers internal gobblers;
    VRFCoordinatorMock internal vrfCoordinator;
    LinkToken internal linkToken;
    Goo internal goo;
    Pages internal pages;
    GobblerReserve internal team;
    GobblerReserve internal community;
    RandProvider internal randProvider;

    bytes32 private keyHash;
    uint256 private fee;

    uint256[] internal ids;

    // Time
    uint256 internal constant TIME0 = 2_000_000_000;

    // Users
    address internal vault;
    address internal constant alice = address(0xAAAA);
    address internal constant bob = address(0xBBBB);
    address internal constant feeTo = address(0xFFFF1);
    address internal constant minter = address(0xFFFF2);

    // Goo
    uint256 internal aliceGooBalance;
    uint256 internal bobGooBalance;

    // Gobblers (in storage to avoid stack too deep)
    uint256[] internal aliceGobblers;
    uint256[] internal aliceGobblersOnlyTwo;
    uint256[] internal aliceSwapOut;
    uint256[] internal aliceSwapIn;
    uint256[] internal aliceWithdraw;
    uint256[] internal bobGobblers;
    uint256[] internal bobGobblersEmpty;
    uint256[] internal bobSwapOut;
    uint256[] internal bobSwapIn;
    uint256[] internal emptyGobblers;

    // Goober Vault Fractions
    uint256 internal aliceGooberBalance;
    uint256 internal bobGooberBalance;

    function setUp() public {
        // Start from TIME0
        vm.warp(TIME0);

        // Deploy Art Gobblers contracts
        utils = new Utilities();
        linkToken = new LinkToken();
        vrfCoordinator = new VRFCoordinatorMock(address(linkToken));
        address gobblerAddress = utils.predictContractAddress(address(this), 4);
        address pagesAddress = utils.predictContractAddress(address(this), 5);
        team = new GobblerReserve(ArtGobblers(gobblerAddress), address(this));
        community = new GobblerReserve(ArtGobblers(gobblerAddress), address(this));
        randProvider = new ChainlinkV1RandProvider({
            _artGobblers: ArtGobblers(gobblerAddress),
            _vrfCoordinator: address(vrfCoordinator),
            _linkToken: address(linkToken),
            _chainlinkKeyHash: keyHash,
            _chainlinkFee: fee
        });
        goo = new Goo({
            _artGobblers: utils.predictContractAddress(address(this), 1),
            _pages: utils.predictContractAddress(address(this), 2)
        });
        gobblers = new ArtGobblers({
            _merkleRoot: keccak256(abi.encodePacked(address(0xCAFE))),
            _mintStart: block.timestamp,
            _goo: goo,
            _pages: Pages(pagesAddress),
            _team: address(team),
            _community: address(community),
            _randProvider: randProvider,
            _baseUri: "base",
            _unrevealedUri: "",
            _provenanceHash: keccak256(abi.encodePacked("provenance"))
        });
        pages = new Pages({
            _mintStart: block.timestamp,
            _goo: goo,
            _community: address(0xBEEF),
            _artGobblers: gobblers,
            _baseUri: ""
        });

        // Deploy Goober contract
        goober = new Goober({
            _gobblersAddress: address(gobblers),
            _gooAddress: address(goo),
            _feeTo: feeTo,
            _minter: minter
        });
        vault = address(goober);
    }

    // # User Story //////////////////////////////////////////////////////////////////////////////////////////////////
    // 
    // As a Goober,
    // I want to pool my Goo and Gobblers with my fellow Goober community,
    // so that we each receive more Goo emissions together than we would on our own.
    // 
    // ## Acceptance Criteria
    // ### Depositing
    // - Should be able to preview a deposit (not inclusive of any fees)
    // - Should be able to deposit Goo and/or Gobblers in exchange for minting GBR vault fractions
    // - Should be able to safe deposit, which ensures a deadline after which the tx will revert,
    //   and minimum amount of GBR fractions to be minted
    // ### Withdrawing
    // - Should be able to preview a withdraw (not inclusive of any fees)
    // - Should be able to withdraw Goo and/or Gobblers in exchange for burning GBR vault fractions
    // - Should be able to safe withdraw, which ensures a deadline after which the tx will revert,
    //   and maximum amount of GBR fractioned to be burned
    // ### Swapping
    // - Should be able to preview a swap (not inclusive of any fees)
    // - Should be able to swap Goo and/or Gobblers in exchange for Goo and/or Gobblers, with a
    //   potential surplus or debt of Goo required
    // - Should be able to safe swap, which ensures a deadline after which the tx will revert, and
    //   a maximum amount of potential surplus or debt of Goo required
    // ### Vault Accounting
    // - Should be able to check total assets of the Goober vault
    // - Should be able to check reserves of the Goober vault
    // - Should be able to check how many GBR fractions would be minted for depositing a given amount of Goo
    // - Should be able to check how much Goo would be withdrawn for burning a given amount of GBR fractions
    // ### Vault Minting
    // - Vault Minter should be able to mint Gobblers using Goo from the Vault
    // ### Vault Fees
    // - Management fee of 2% should be assessed on all deposits and withdraws, paid in Goo to Vault Admin
    // - Performance fee of 10% should be assessed on all deposits and withdraws, if the growth
    //   in k is sufficient to offset any accrued kDebt, paid in Goo to Vault Admin address
    // - Swap fee of 3% should be assessed on all swaps, paid in GBR to the Vault itself
    // ### Vault Admin
    // - Vault Admin should be able to flag/unflag a Gobbler, disallowing deposit into the Vault
    // - Vault Admin should be able to skim any erroneously accrued Goo from the Vault
    // - Vault Admin should be able to set new Vault Admin
    // - Vault Admin should be able to set new Vault Minter

    // # Scenario ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // V = Vault, A = Alice, B = Bob, F = FeeTo
    //
    // gbr = Goober vault fractions
    // goo = physically held Goo tokens
    // gbbl = physically held Gobbler NFTs
    // mult = Gobbler multiplier for account
    //
    //  _____________________________________________________________________________________________________________
    // | V gbr | V goo | V gbbl | V mult | A gbr | A goo | A gbbl | A mult | B gbr | B goo | B gbbl | B mult | F goo |
    // |=============================================================================================================|
    // | 0. Vault, Alice, Bob, FeeTo starting balances                                                               |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |     0 |     0 |      0 |     0 |      0 |  2000 |      0 |      0 |     0 |  2000 |      0 |      0 |     0 |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 1. Alice adds 1000 Goo and mints 3 Gobblers                                                                 |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |     0 |     0 |      0 |     0 |      0 |  1000 |      3 |      0 |     0 |     0 |      0 |      0 |     0 |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 2. Bob adds 500 Goo and mints 1 Gobbler                                                                     |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |     0 |     0 |      0 |     0 |      0 |  1000 |      3 |      0 |     0 |  1500 |      1 |      0 |     0 |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 3. Gobblers reveal – Alice gets a 9, 8, and 6 and Bob gets a Gobbler 9                                      |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |     0 |     0 |      0 |     0 |      0 |  1000 |      3 |     23 |     0 |  1500 |      1 |      9 |     0 |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 4. Alice deposits 200 Goo and Gobblers 9, 8, minting ~57.1433 GBR vault fractions                           |
    // | (FeeTo receives XYZ Goo as management fee, No performance fee bc there's no growth in k since lastK)        |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   200 |     0 |      2 |    17 |    ~57 |   800 |      1 |      6 |     0 |  1500 |      1 |      9 |   XYZ |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 5. Vault accrues Goo for 1 hour, receiving XYZ GBR in emissions from 2 Gobblers with multiple 17            |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   200 |   XYZ |      2 |    17 |    ~57 |   800 |      1 |      6 |     0 |  1500 |      1 |      9 |   XYZ |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 6. Bob swaps in a Gobbler 9 for 500 Goo and a Gobbler 8 out (Vault receives XYZ Goo as swap fee)            |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   200 |   XYZ |      2 |    18 |    ~57 |   800 |      1 |      6 |     0 |  2000 |      1 |      8 |   XYZ |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 7. Vault accrues Goo for 1 hour, receiving XYZ GBR in emissions from 2 Gobblers with multiple 20            |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   200 |   XYZ |      2 |    18 |    ~57 |   800 |      1 |      6 |     0 |  2000 |      1 |      8 |   XYZ |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 8. Vault mints 1 Gobbler for ~59.7 Goo                                                                      |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   200 |   XYZ |      3 |    18 |    ~57 |   800 |      1 |      6 |     0 |  2000 |      1 |      8 |   XYZ |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 9. Alice swaps in a Gobbler 6 and XYZ Goo for a Gobbler 9 out                                               |
    // | (Vault receives XYZ Goo as swap fee, Vault records kDebt)                                                   |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   200 |   XYZ |      3 |    15 |    ~57 |   XYZ |      1 |      9 |     0 |  2000 |      1 |      8 |   XYZ |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 10. Bob deposits 10 Goo, minting him ~17.0487 GBR fractions                                                 |
    // | (This triggers a small performance fee, but not enough to fully offset the kDebt so no performance fee)     |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   200 |   XYZ |      3 |    15 |    ~57 |   XYZ |      1 |      9 |   ~17 |  1990 |      1 |      8 |   XYZ |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 11. Gobblers reveal – Vault gets a Gobbler 6, plus ~55 Goo in emissions for the 1 day which elapsed         |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   200 |   XYZ |      3 |    21 |    ~57 |   XYZ |      1 |      9 |   ~17 |  1990 |      1 |      8 |   XYZ |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 12. Bob deposits 10 more Goo, minting him XYZ GBR fractions                                                 |
    // | (Between the swap fee and the mint, there's now enough to offset the kDebt so a performance fee is assessed)|
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   200 |   XYZ |      3 |    21 |    ~57 |   XYZ |      1 |      9 |   XYZ |  1980 |      1 |      8 |   XYZ |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 13. Vault accrues Goo for 1 hour, receiving ~2.9679 GBR in emissions from 3 Gobblers with multiple 21       |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   200 |   XYZ |      3 |    21 |    ~57 |   XYZ |      1 |      9 |   XYZ |  1980 |      1 |      8 |   XYZ |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 14. Bob withdraws XYZ Goo for XYZ GBR fractions (FeeTo accrues XYZ Goo as fee)                              |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   XYZ |   XYZ |      3 |    21 |    ~57 |   XYZ |      1 |      9 |   XYZ |  1980 |      1 |      8 |   XYZ |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 15. Alice withdraws XYZ Goo and 2 Gobbler 6s for ~35.5816 GBR fractions (FeeTo accrues XYZ Goo as fee)      |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   XYZ |   XYZ |      1 |     9 |    ~57 |   XYZ |      1 |     21 |   XYZ |  1980 |      1 |      8 |   XYZ |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|

    function testMultipleDepositSwapMintWithdraw() public {
        // 0. Vault, Alice, Bob, FeeTo starting balances
        _writeTokenBalance(alice, address(goo), 2000 ether);
        _writeTokenBalance(bob, address(goo), 2000 ether);
        vm.startPrank(alice);
        goo.approve(vault, type(uint256).max);
        gobblers.setApprovalForAll(vault, true);
        vm.stopPrank();
        vm.startPrank(bob);
        goo.approve(vault, type(uint256).max);
        gobblers.setApprovalForAll(vault, true);
        vm.stopPrank();

        assertEq(goo.balanceOf(vault), 0);
        assertEq(goo.balanceOf(alice), 2000 ether);
        assertEq(goo.balanceOf(bob), 2000 ether);
        assertEq(gobblers.gooBalance(vault), 0);
        assertEq(gobblers.gooBalance(alice), 0);
        assertEq(gobblers.gooBalance(bob), 0);
        assertEq(gobblers.balanceOf(vault), 0);
        assertEq(gobblers.balanceOf(alice), 0);
        assertEq(gobblers.balanceOf(bob), 0);
        (uint256 vaultGoo, uint256 vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, 0);
        assertEq(vaultMult, 0);
        (uint112 vaultGooReserve, uint112 vaultGobblersReserve, uint32 vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, 0);
        assertEq(vaultGobblersReserve, 0);
        assertEq(vaultLastTimestamp, 0);

        // 1. Alice adds 1000 Goo and mints 3 Gobblers
        vm.startPrank(alice);
        gobblers.addGoo(1000 ether);
        aliceGobblers = new uint256[](3);
        aliceGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        aliceGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        aliceGobblers[2] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        assertEq(goo.balanceOf(vault), 0);
        assertEq(goo.balanceOf(alice), 1000 ether);
        assertEq(goo.balanceOf(bob), 2000 ether);
        assertEq(gobblers.gooBalance(vault), 0);
        assertEq(gobblers.balanceOf(vault), 0);
        assertEq(gobblers.balanceOf(alice), 3);
        assertEq(gobblers.balanceOf(bob), 0);
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, 0);
        assertEq(vaultMult, 0);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, 0);
        assertEq(vaultGobblersReserve, 0);
        assertEq(vaultLastTimestamp, 0);

        // 2. Bob adds 500 Goo and mints 1 Gobbler
        vm.startPrank(bob);
        gobblers.addGoo(500 ether);
        bobGobblers = new uint256[](1);
        bobGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        assertEq(goo.balanceOf(vault), 0);
        assertEq(goo.balanceOf(alice), 1000 ether);
        assertEq(goo.balanceOf(bob), 1500 ether);
        assertEq(gobblers.gooBalance(vault), 0);
        assertEq(gobblers.balanceOf(vault), 0);
        assertEq(gobblers.balanceOf(alice), 3);
        assertEq(gobblers.balanceOf(bob), 1);
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, 0);
        assertEq(vaultMult, 0);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, 0);
        assertEq(vaultGobblersReserve, 0);
        assertEq(vaultLastTimestamp, 0);

        // 3. Gobblers reveal – Alice gets a 9, 8, and 6 and Bob gets a Gobbler 9
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(4, "seed");

        assertEq(gobblers.ownerOf(1), alice);
        assertEq(gobblers.getGobblerEmissionMultiple(1), 9);
        assertEq(gobblers.ownerOf(2), alice);
        assertEq(gobblers.getGobblerEmissionMultiple(2), 8);
        assertEq(gobblers.ownerOf(3), alice);
        assertEq(gobblers.getGobblerEmissionMultiple(3), 6);
        assertEq(gobblers.ownerOf(4), bob);
        assertEq(gobblers.getGobblerEmissionMultiple(4), 9);

        // 4. Alice deposits 200 Goo and Gobblers 9, 8, minting ~57.1433 GBR vault fractions
        // (FeeTo receives XYZ Goo as management fee, No performance fee bc there's no growth in k since lastK)
        aliceGobblersOnlyTwo = new uint256[](2);
        aliceGobblersOnlyTwo[0] = aliceGobblers[0];
        aliceGobblersOnlyTwo[1] = aliceGobblers[1];
        vm.startPrank(alice);
        uint256 aliceFractions = goober.deposit(aliceGobblersOnlyTwo, 200 ether, alice);
        vm.stopPrank();

        // Check Goo is transferred into vault,
        uint256 expectedGoo = 200 ether;
        uint256 expectedMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(2);
        assertEq(gobblers.gooBalance(vault), expectedGoo);
        // Gobblers are transferred into vault,
        assertEq(gobblers.ownerOf(aliceGobblers[0]), vault);
        assertEq(gobblers.ownerOf(aliceGobblers[1]), vault);
        // Fractions are minted to depositor,
        assertEq(goober.balanceOf(alice), aliceFractions);
        // Total assets and reserve balances are updated,
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, expectedGoo);
        assertEq(vaultMult, expectedMult);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, expectedGoo);
        assertEq(vaultGobblersReserve, gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(2));
        assertEq(vaultLastTimestamp, TIME0 + 1 days);
        // and the protocol admin accrues XYZ Goo in management fees. (management fee is 2% of total deposit)

        // 5. Vault accrues Goo for 1 hour, receiving XYZ GBR in emissions from 2 Gobblers with multiple 17
        vm.warp(TIME0 + 1 days + 1 hours);

        expectedGoo += 2_436_941_761_741_097_378;
        assertEq(gobblers.gooBalance(vault), expectedGoo);
        assertEq(gobblers.balanceOf(vault), 2);
        assertEq(gobblers.balanceOf(alice), 1);
        assertEq(gobblers.balanceOf(bob), 1);
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, expectedGoo);
        assertEq(vaultMult, expectedMult);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, expectedGoo);
        assertEq(vaultGobblersReserve, expectedMult);
        assertEq(vaultLastTimestamp, TIME0 + 1 days);

        // 6. Bob swaps in a Gobbler 9 for some Goo and a Gobbler 8 out (Vault receives XYZ Goo as swap fee)
        bobSwapIn = new uint256[](1);
        bobSwapIn[0] = 4; // Bob's gobbler
        bobSwapOut = new uint256[](1);
        bobSwapOut[0] = 2; // Alice's 2nd gobbler
        vm.startPrank(bob);

        int256 bobErroneousGoo = goober.previewSwap(bobSwapIn, 0, bobSwapOut, 0);
        assertEq(bobErroneousGoo, -10_992_257_043_437_332_960); // Bob will get ~10.9 Goo back before swap fee

        IGoober.SwapParams memory bobSwap = IGoober.SwapParams(bobSwapOut, 10 ether, bobSwapIn, 0, bob, "");
        goober.swap(bobSwap);
        vm.stopPrank();

        expectedGoo = 200 ether - 10 ether + 2_436_941_761_741_097_378; // Bob receives ~7.5 Goo back, after ~2.5 swap fee // Bob receives 7_563_058_238_258_902_622, after 2_436_941_761_741_097_378 swap fee
        expectedMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(4); // new vault multiple after swap
        assertEq(gobblers.gooBalance(vault), expectedGoo);
        assertEq(goo.balanceOf(bob), 1500 ether + 10 ether);
        // TODO check Bob goober balance
        assertEq(gobblers.balanceOf(vault), 2);
        assertEq(gobblers.balanceOf(alice), 1);
        assertEq(gobblers.balanceOf(bob), 1);
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, expectedGoo);
        assertEq(vaultMult, expectedMult);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, expectedGoo);
        assertEq(vaultGobblersReserve, expectedMult);
        assertEq(vaultLastTimestamp, TIME0 + 1 days + 1 hours); // new time

        // 7. Vault accrues Goo (receives XYZ GBR in emissions from Gobblers)
        vm.warp(TIME0 + 1 days + 2 hours);

        expectedGoo += 2_460_087_857_714_628_484; // vault receives ~2.4 Goo in emissions
        assertEq(gobblers.gooBalance(vault), expectedGoo);
        assertEq(gobblers.balanceOf(vault), 2);
        assertEq(gobblers.balanceOf(alice), 1);
        assertEq(gobblers.balanceOf(bob), 1);
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, expectedGoo);
        assertEq(vaultMult, expectedMult);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, expectedGoo);
        assertEq(vaultGobblersReserve, expectedMult);
        assertEq(vaultLastTimestamp, TIME0 + 1 days + 1 hours);

        // 8. Vault mints 1 Gobbler for ~59.7 Goo
        vm.prank(minter);
        goober.mintGobbler();

        expectedGoo -= 59_772_562_115_376_111_594; // new balance, after paying ~59.7 Goo to mint
        expectedMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(4);
        assertEq(gobblers.gooBalance(vault), expectedGoo);
        assertEq(gobblers.balanceOf(vault), 3);
        assertEq(gobblers.balanceOf(alice), 1);
        assertEq(gobblers.balanceOf(bob), 1);
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, expectedGoo);
        assertEq(vaultMult, expectedMult);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, expectedGoo);
        assertEq(vaultGobblersReserve, expectedMult);
        assertEq(vaultLastTimestamp, TIME0 + 1 days + 2 hours); // new time

        // 9. Alice swaps in a Gobbler 6 and XYZ Goo for a Gobbler 9 out
        // (Vault receives XYZ Goo as swap fee, Vault records kDebt)
        aliceSwapIn = new uint256[](1);
        aliceSwapIn[0] = 3; // Alice's Gobbler 6
        aliceSwapOut = new uint256[](1);
        aliceSwapOut[0] = 4; // Bob's Gobbler 9

        int256 aliceErroneousGoo = goober.previewSwap(aliceSwapIn, 0, aliceSwapOut, 0);
        assertEq(aliceErroneousGoo, 27_301_611_343_663_367_346); // Alice will need to swap in at least ~27.3 Goo, before swap fee

        vm.startPrank(alice);
        IGoober.SwapParams memory aliceSwap = IGoober.SwapParams(aliceSwapOut, 0, aliceSwapIn, 30 ether, alice, "");
        goober.swap(aliceSwap);
        vm.stopPrank();

        expectedGoo += 30 ether;
        expectedMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(3); // new vault multiple after swap
        assertEq(gobblers.gooBalance(vault), expectedGoo);
        assertEq(goo.balanceOf(alice), 800 ether - 30 ether);
        // TODO check Alice goober balance
        assertEq(gobblers.balanceOf(vault), 3);
        assertEq(gobblers.balanceOf(alice), 1);
        assertEq(gobblers.balanceOf(bob), 1);
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, expectedGoo);
        assertEq(vaultMult, expectedMult);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, expectedGoo);
        assertEq(vaultGobblersReserve, expectedMult);
        assertEq(vaultLastTimestamp, TIME0 + 1 days + 2 hours);

        // 10. Bob deposits 10 Goo, minting him ~17.0487 GBR fractions
        // (This triggers a small performance fee, but not enough to fully offset the kDebt so no performance fee)
        vm.prank(bob);
        emptyGobblers = new uint256[](0);
        uint256 bobFractions = goober.deposit(emptyGobblers, 10 ether, bob);

        expectedGoo += 10 ether;
        assertEq(gobblers.gooBalance(vault), expectedGoo);
        assertEq(goober.balanceOf(bob), bobFractions); // Bob is minted ~17 GBR fractions
        assertEq(gobblers.balanceOf(vault), 3);
        assertEq(gobblers.balanceOf(alice), 1);
        assertEq(gobblers.balanceOf(bob), 1);
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, expectedGoo);
        assertEq(vaultMult, expectedMult);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, expectedGoo);
        assertEq(vaultGobblersReserve, expectedMult);
        assertEq(vaultLastTimestamp, TIME0 + 1 days + 2 hours);

        // 11. Gobblers reveal – Vault gets a Gobbler 6, plus ~55 Goo in emissions for the 1 day which elapsed
        vm.warp(TIME0 + 1 days + 2 hours + 1 days);
        _setRandomnessAndReveal(1, "seed2");

        assertEq(gobblers.getGobblerEmissionMultiple(5), 6);
        expectedGoo += 55_002_970_768_153_471_144; // Goo emissions
        expectedMult += gobblers.getGobblerEmissionMultiple(5); // new vault multiple after reveal
        assertEq(gobblers.gooBalance(vault), expectedGoo);
        assertEq(gobblers.balanceOf(vault), 3);
        assertEq(gobblers.balanceOf(alice), 1);
        assertEq(gobblers.balanceOf(bob), 1);
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, expectedGoo);
        assertEq(vaultMult, expectedMult);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, expectedGoo);
        assertEq(vaultGobblersReserve, expectedMult);
        assertEq(vaultLastTimestamp, TIME0 + 1 days + 2 hours);

        // 12. Bob deposits 10 more Goo, minting him XYZ GBR fractions
        // (Between the swap fee and the mint, there's now enough to offset the kDebt so a performance fee is assessed)
        vm.prank(bob);
        bobFractions += goober.deposit(emptyGobblers, 10 ether, bob);

        expectedGoo += 10 ether;
        assertEq(gobblers.gooBalance(vault), expectedGoo);
        assertEq(goober.balanceOf(bob), bobFractions); // Bob is only minted ~2 GBR fractions, after performance fee is assessed
        assertEq(gobblers.balanceOf(vault), 3);
        assertEq(gobblers.balanceOf(alice), 1);
        assertEq(gobblers.balanceOf(bob), 1);
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, expectedGoo);
        assertEq(vaultMult, expectedMult);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, expectedGoo);
        assertEq(vaultGobblersReserve, expectedMult);
        assertEq(vaultLastTimestamp, TIME0 + 1 days + 2 hours + 1 days); // new time

        // 13. Vault accrues Goo for 1 hour, receiving ~2.9679 GBR in emissions from 3 Gobblers with multiple 21
        vm.warp(TIME0 + 1 days + 2 hours + 1 days + 1 hours);

        expectedGoo += 2_967_939_719_600_851_528;
        assertEq(gobblers.gooBalance(vault), expectedGoo);
        assertEq(gobblers.balanceOf(vault), 3);
        assertEq(gobblers.balanceOf(alice), 1);
        assertEq(gobblers.balanceOf(bob), 1);
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, expectedGoo);
        assertEq(vaultMult, expectedMult);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, expectedGoo);
        assertEq(vaultGobblersReserve, expectedMult);
        assertEq(vaultLastTimestamp, TIME0 + 1 days + 2 hours + 1 days);

        // 14. Bob withdraws 20 Goo for ~0.3670 GBR fractions (FeeTo accrues XYZ Goo as fee)
        vm.prank(bob);
        uint256 fractionsWithdrawn = goober.withdraw(emptyGobblers, 20 ether, bob, bob);

        expectedGoo -= 20 ether;
        assertEq(gobblers.gooBalance(vault), expectedGoo);
        assertEq(goo.balanceOf(bob), 1500 ether + 10 ether);
        // TODO assertEq(goober.balanceOf(bob), 666 ether); // now ~0.3670 GRB fractions less
        assertEq(gobblers.balanceOf(vault), 3);
        assertEq(gobblers.balanceOf(alice), 1);
        assertEq(gobblers.balanceOf(bob), 1);
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, expectedGoo);
        assertEq(vaultMult, expectedMult);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, expectedGoo);
        assertEq(vaultGobblersReserve, expectedMult);
        assertEq(vaultLastTimestamp, TIME0 + 1 days + 2 hours + 1 days + 1 hours); // new time

        // 15. Alice withdraws 10 Goo and 2 Gobbler 6s for ~35.5816 GBR fractions (FeeTo accrues XYZ Goo as fee)
        vm.prank(alice);
        aliceWithdraw = new uint256[](2);
        aliceWithdraw[0] = 3; // Alice's Gobbler 6
        aliceWithdraw[1] = 5; // Gobbler 6 which the Vault minted
        fractionsWithdrawn = goober.withdraw(aliceWithdraw, 10 ether, alice, alice);

        expectedGoo -= 10 ether;
        expectedMult = gobblers.getGobblerEmissionMultiple(1);
        assertEq(gobblers.gooBalance(vault), expectedGoo);
        assertEq(goo.balanceOf(alice), 800 ether - 30 ether + 10 ether);
        // TODO assertEq(goober.balanceOf(alice), 777 ether); // now ~35.5816 GRB fractions less // 35_581_634_925
        assertEq(gobblers.balanceOf(vault), 1); // 2 Gobblers less
        assertEq(gobblers.balanceOf(alice), 3); // 2 Gobblers more
        assertEq(gobblers.getUserEmissionMultiple(alice), 21); // multipliers 9, 6, and 6
        assertEq(gobblers.balanceOf(bob), 1);
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, expectedGoo);
        assertEq(vaultMult, expectedMult);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, expectedGoo);
        assertEq(vaultGobblersReserve, expectedMult);
        assertEq(vaultLastTimestamp, TIME0 + 1 days + 2 hours + 1 days + 1 hours);
    }

    // emit log_named_uint("Alice before", goober.balanceOf(alice));
    // emit log_named_uint("Alice after", goober.balanceOf(alice));

    // emit log_named_uint("Goo before", gobblers.gooBalance(vault));
    // emit log_named_uint("Goo after", gobblers.gooBalance(vault));

    // and the protocol admin accrues XYZ Goo in management fees.
    // (performance fee is 10% of the dilution in k beyond kLast)



    //
    // Alice will mint IDs 1-3, Bob will mint ID 4, Vault will mint ID 5
    //
    // Token ID 1 will have Multiplier 9
    // Token ID 2 will have Multiplier 8
    // Token ID 3 will have Multiplier 6
    // Token ID 4 will have Multiplier 9
    // Token ID 5 will have Multiplier 6



    // TODO Invariant ideas
    // Goober Vault GBR balance = xyz
    // Goober Vault Mult = Σ depositor Gobbler multipliers
    // Goober Vault Goo reserve = Σ depositor Goo balances + Goo emissions + Swap fees accrued
    // Goober Vault Gobblers reserve = Σ depositor Gobbler balances
    // Goober Admin xyz

    // TODO
    // function testFuzzDeposit(
    //     uint256 gooAmount1,
    //     uint256 gobblerAmount1,
    //     uint256 gooAmount2,
    //     uint256 gobblerAmount2,
    //     // uint256 gooAmount3,
    //     // uint256 gobblerAmount3,
    //     // uint256 gooAmount4,
    //     // uint256 gobblerAmount4,
    //     // uint256 gooAmount5,
    //     // uint256 gobblerAmount5,
    //     uint256 timeSeed
    // ) public {
    //     gooAmount1 = bound(gooAmount1, 100 ether, 1000 ether);
    //     gobblerAmount1 = bound(gobblerAmount1, 1, 3);
    //     gooAmount2 = bound(gooAmount2, 100 ether, 1000 ether);
    //     gobblerAmount2 = bound(gobblerAmount2, 1, 3);
    //     // gooAmount3 = bound(gooAmount3, 100 ether, 1000 ether);
    //     // gobblerAmount3 = bound(gobblerAmount3, 1, 3);
    //     // gooAmount4 = bound(gooAmount4, 100 ether, 1000 ether);
    //     // gobblerAmount4 = bound(gobblerAmount4, 1, 3);
    //     // gooAmount5 = bound(gooAmount5, 100 ether, 1000 ether);
    //     // gobblerAmount5 = bound(gobblerAmount5, 1, 3);

    //     // Broken -- getting an overflow from ArtGobblers.mintFromGoo()

    //     // vm.prank(users[1]);
    //     // _addGooAndMintGobblers(gooAmount1, gobblerAmount1);
    //     // vm.prank(users[2]);
    //     // _addGooAndMintGobblers(gooAmount2, gobblerAmount2);
    //     // vm.prank(users[3]);
    //     // _addGooAndMintGobblers(gooAmount3, gobblerAmount3);
    //     // vm.prank(users[4]);
    //     // _addGooAndMintGobblers(gooAmount4, gobblerAmount4);
    //     // vm.prank(users[5]);
    //     // _addGooAndMintGobblers(gooAmount5, gobblerAmount5);

    //     // vm.warp(TIME0 + 1 days);
    //     // _setRandomnessAndReveal(
    //     //     gobblerAmount1 + gobblerAmount2 + gobblerAmount3 + gobblerAmount4 + gobblerAmount5, "seed"
    //     // );

    //     emit log_string("hello world");
    // }

    /*//////////////////////////////////////////////////////////////
                        Test Helpers
    //////////////////////////////////////////////////////////////*/

    function _writeTokenBalance(address who, address token, uint256 amt) internal {
        stdstore.target(token).sig(IERC20(token).balanceOf.selector).with_key(who).checked_write(amt);
    }

    /// @dev Call back vrf with randomness and reveal gobblers.
    function _setRandomnessAndReveal(uint256 numReveal, string memory seed) internal {
        bytes32 requestId = gobblers.requestRandomSeed();
        uint256 randomness = uint256(keccak256(abi.encodePacked(seed)));
        // call back from coordinator
        vrfCoordinator.callBackWithRandomness(requestId, randomness, address(randProvider));
        gobblers.revealGobblers(numReveal);
    }
}
