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

contract GooberOtherTest is Test {
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

    // Gobblers
    uint256[] internal aliceGobblers;
    uint256[] internal aliceGobblersOnlyTwo;
    uint256[] internal bobGobblers;
    uint256[] internal bobGobblersEmpty;
    uint256[] internal bobSwapOut;

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

    // Scenario
    // 
    // V = Vault, A = Alice, B = Bob, F = FeeTo
    // gbr = Goober vault fractions
    // goo = physically held Goo tokens
    // gbbl = physically held Gobbler NFTs
    // mult = Gobbler multiplier for account
    // 
    //  _____________________________________________________________________________________________________________
    // | V gbr | V goo | V gbbl | V mult | A gbr | A goo | A gbbl | A mult | B gbr | B goo | B gbbl | B mult | F goo |
    // |=============================================================================================================|



    //  ________________________________________________________________________________________
    // | V gbr | V mult | A gbr | A goo | A gbblrs | A mult | B gbr | B goo | B gbblrs | B mult |
    // |========================================================================================|    
    // | 0. Vault, Alice, Bob starting balances
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |     0 |      0 |     0 |  2000 |        0 |      0 |     0 |  2000 |        0 |      0 |
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 1. Alice adds 1000 Goo and mints 3 Gobblers
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |     0 |      0 |     0 |  1000 |        3 |      0 |     0 |     0 |        0 |      0 |
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 2. Bob adds 500 Goo and mints 1 Gobbler
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |     0 |      0 |     0 |  1000 |        3 |      0 |     0 |  1500 |        1 |      0 |
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 3. Gobblers reveal – Alice gets a 9, 8, 6 and Bob gets a 9
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |     0 |      0 |     0 |  1000 |        3 |     23 |     0 |  1500 |        1 |      9 |
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 4. Alice deposits 200 Goo and Gobblers 9, 8
    // | (Mints ~57.1433 GBR, No performance fee bc no growth in k since lastK as initial deposit)
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |   200 |     17 |   ~57 |   800 |        1 |      6 |     0 |  1500 |        1 |      9 |
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 5. Vault accrues Goo for 1 hour (receives XYZ GBR in emissions from Gobblers)
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |   200 |     17 |   ~57 |   800 |        1 |      6 |     0 |  1500 |        1 |      9 | TODO add V goo and gbblrs
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 6. Bob swaps in Gobbler 9 for 500 Goo and Gobbler 6 out
    // | (Swap requires additional XYZ GOO, Vault accrues XYZ Goo as swap fee)
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |   200 |     20 |   ~57 |   800 |        1 |      6 |     0 |  2000 |        1 |      6 | TODO check the actual in previewSwap() -- won't Bob get some Goo back?
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 7. Vault accrues Goo (receives XYZ GBR in emissions from Gobblers)
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |   XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ | TODO add V
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 8. Vault mints 1 Gobbler
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |   200 |     20 |   ~57 |   800 |        1 |      6 |     0 |  2000 |        1 |      6 | TODO add V
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 9. Alice swaps in Gobbler 6 and XYZ Goo for Gobbler 8 out
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |   XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 10. Bob deposits 10 Goo (Triggers a small fee, but not enough to fully offset the debt)
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |   XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 11. Gobblers reveal – Vault gets a XYZ
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |   XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 12. Deposit
    // | (Between the swap fee and the mint, there's now enough to offset the debt so a performance fee is assessed)
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |   XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 13. Vault accrues Goo (receives XYZ GBR in emissions from Gobblers)
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |   XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 14. Bob withdraws XYZ Goo and XYZ Gobblers for XYZ fractions (Admin accrues XYZ Goo as fee)
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |   XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // | 15. Alice withdraws XYZ Goo and XYZ Gobblers for XYZ fractions (Admin accrues XYZ Goo as fee)
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
    // |   XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |
    // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|

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

        // Check TODO
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
    
        // Check TODO
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

        // 3. Gobblers reveal – Alice gets a 9, 8, 6 and Bob gets a 9
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(4, "seed");

        // Check TODO
        assertEq(gobblers.ownerOf(1), alice);
        assertEq(gobblers.getGobblerEmissionMultiple(1), 9);
        assertEq(gobblers.ownerOf(2), alice);
        assertEq(gobblers.getGobblerEmissionMultiple(2), 8);
        assertEq(gobblers.ownerOf(3), alice);
        assertEq(gobblers.getGobblerEmissionMultiple(3), 6);
        assertEq(gobblers.ownerOf(4), bob);
        assertEq(gobblers.getGobblerEmissionMultiple(4), 9);

        // 4. Alice deposits 200 Goo and Gobblers 9, 8 (mints 57.1433 GBR, No performance fee because no growth in k since lastK on initial deposit)
        aliceGobblersOnlyTwo = new uint256[](2);
        aliceGobblersOnlyTwo[0] = aliceGobblers[0];
        aliceGobblersOnlyTwo[1] = aliceGobblers[1];
        vm.startPrank(alice);
        uint256 aliceFractions = goober.deposit(aliceGobblersOnlyTwo, 200 ether, alice);
        vm.stopPrank();

        // // Check Goo is transferred into vault,
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

        // 5. Vault accrues Goo for 1 hour (receives XYZ GBR in emissions from Gobblers)
        vm.warp(TIME0 + 1 days + 1 hours);

        // Check TODO
        expectedGoo = 200 ether + 2_436_941_761_741_097_378; // TODO sqrt(vaultMult * vaultGoo * vaultGobblers)
        expectedMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(2);
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

        // 6. Bob swaps in Gobbler 9 for 500 Goo and Gobbler 6 out (costs additional XYZ GBR, Vault accrues XYZ Goo as fee)
        bobSwapOut = new uint256[](1);
        bobSwapOut[0] = aliceGobblers[1];
        vm.startPrank(bob);
        IGoober.SwapParams memory swap =
            IGoober.SwapParams(bobSwapOut, 0, bobGobblers, 500 ether, bob, "");
        goober.swap(swap);
        vm.stopPrank();

        // Check TODO
        expectedGoo = 200 ether + 500 ether + 2_436_941_761_741_097_378; // TODO
        expectedMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(4); // alice's gobbler swapped for bob's
        assertEq(gobblers.gooBalance(vault), expectedGoo);
        // TODO bob goo balance
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

        // Check TODO
        expectedGoo = 200 ether + 500 ether + 7_129_960_172_910_254_154; // TODO
        expectedMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(4);
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

        // 8. Vault mints 1 Gobbler
        vm.prank(minter);
        goober.mintGobbler();

         // Check TODO
        expectedGoo = 200 ether + 500 ether + 7_129_960_172_910_254_154; // TODO
        expectedMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(4) + gobblers.getGobblerEmissionMultiple(5); // new multiplier
        assertEq(gobblers.gooBalance(vault), expectedGoo);
        assertEq(gobblers.balanceOf(vault), 2); // don't count yet, bc not revealed
        assertEq(gobblers.balanceOf(alice), 1);
        assertEq(gobblers.balanceOf(bob), 1);
        (vaultGoo, vaultMult) = goober.totalAssets();
        assertEq(vaultGoo, expectedGoo);
        assertEq(vaultMult, expectedMult);
        (vaultGooReserve, vaultGobblersReserve, vaultLastTimestamp) = goober.getReserves();
        assertEq(vaultGooReserve, expectedGoo);
        assertEq(vaultGobblersReserve, expectedMult);
        assertEq(vaultLastTimestamp, TIME0 + 1 days + 2 hours); // new time

        // Bot takes out Goo
        // Adds back Gobbler with mult 0
        // This decreases k, so we track in kDebt
        // Things happen
        // Reveal happens
        // Now mult increases
        // When the next deposit/withdraw happens, we offset any growth against the existing kDebt, 
        // then take the 10% performance fee 

        // 9. Alice swaps Gobbler 6 for Goo (gets a small fee)



        
        // and the protocol admin accrues XYZ Goo in management fees.
        // (performance fee is 10% of the dilution in k beyond kLast)
        // TODO        

        // 10. Small deposit – triggers a small fee, but not enough to fully offset the debt

        // 11. Gobblers reveal – Vault gets a XYZ

        // vm.warp(TIME0 + 1 days + 1 hours + 1 days);
        // _setRandomnessAndReveal(1, "seed2");

        // 

        // 

        // 12. Deposit – between the swap fee and the mint, there's now enough to offset the debt

        // 

        // 13. Vault accrues Goo (receives XYZ GBR in emissions from Gobblers)

        // 14. Bob withdraws XYZ Goo and XYZ Gobblers for XYZ fractions (Admin accrues XYZ Goo as fee)
        // and the protocol admin accrues XYZ Goo in management fees.
        // (performance fee is 10% of the dilution in k beyond kLast)
        // TODO        

        // 15. Alice withdraws XYZ Goo and XYZ Gobblers for XYZ fractions (Admin accrues XYZ Goo as fee)
        // and the protocol admin accrues XYZ Goo in management fees.
        // (performance fee is 10% of the dilution in k beyond kLast)
        // TODO        

    }



        
  



        // 
        // Goober Vault GBR balance = xyz
        // Goober Vault Mult = Σ depositor Gobbler multipliers
        // Goober Vault Goo reserve = Σ depositor Goo balances + Goo emissions + Swap fees accrued
        // Goober Vault Gobblers reserve = Σ depositor Gobbler balances
        // Goober Admin xyz
  
        // | 1. Alice and Bob have a starting balance of 500 Goo and 0 Gobblers                     |
        // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
        // |   XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |
        // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|



        // | 1. Alice and Bob have a starting balance of 500 Goo and 0 Gobblers                     |
        // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
        // |     0 |      0 |     0 |     0 |        0 |      0 |     0 |     0 |        0 |      0 |
        // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|



        // | 1. Alice mints 2000 shares (costs 2000 tokens)                              |
        // |-----------|---------|---------|------------|---------|---------|------------|
        // |         0 |       0 |       0 |          0 |       0 |       0 |          0 
        // |-----------|---------|---------|------------|---------|---------|------------|


    // TODO
    // function testDepositIntegration(
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

