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

    // Storage to avoid stack too deep error
    uint256[] internal aliceGobblers;
    uint256[] internal aliceGobblersOnlyTwo;
    uint256[] internal bobGobblers;
    uint256[] internal bobGobblersEmpty;
    uint256[] internal bobSwapOut;

    uint256 internal constant TIME0 = 2_000_000_000;

    function setUp() public {
        vm.warp(TIME0);

        utils = new Utilities();
        linkToken = new LinkToken();
        vrfCoordinator = new VRFCoordinatorMock(address(linkToken));

        // Deploy Art Gobblers contracts
        // Gobblers contract will be deployed after 4 contract deploys, and pages after 5.
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

        // Deploy Goober
        goober = new Goober({
            _gobblersAddress: address(gobblers),
            _gooAddress: address(goo),
            _feeTo: address(0xFFFF1),
            _minter: address(0xFFFF2)
        });
    }

    function testMultipleDepositSwapWithdraw() public {
        // 1. Vault, Alice, Bob starting balances
        address vault = address(goober);
        address alice = address(0xAAAA);
        address bob = address(0xBBBB);
        address minter = address(0xFFFF2);

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

        // 2. Alice adds 1000 Goo and mints 3 Gobblers
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

        // 3. Bob adds 500 Goo and mints 1 Gobbler
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

        // 4. Gobblers reveal – Alice gets a 9, 8, 6 and Bob gets a 9
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

        // 5. Alice deposits 200 Goo and Gobblers 9, 8 (mints 57.1433 GBR, No performance fee because no growth in k since lastK on initial deposit)
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

        // 6. Vault accrues Goo for 1 hour (receives XYZ GBR in emissions from Gobblers)
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

        // 7. Bob swaps 500 Goo and Gobbler 6 for Gobbler 8 (costs additional XYZ GBR, Vault accrues XYZ Goo as fee)
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

        // 8. Vault accrues Goo (receives XYZ GBR in emissions from Gobblers)        
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

        // 9. Vault mints 1 Gobbler
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

        // 10. Alice swaps Gobbler 6 for Goo (gets a small fee)



        
        // and the protocol admin accrues XYZ Goo in management fees.
        // (performance fee is 10% of the dilution in k beyond kLast)
        // TODO        

        // 11. Small deposit – triggers a small fee, but not enough to fully offset the debt

        // 12. Gobblers reveal – Vault gets a XYZ

        // vm.warp(TIME0 + 1 days + 1 hours + 1 days);
        // _setRandomnessAndReveal(1, "seed2");

        // 

        // 

        // 13. Deposit – between the swap fee and the mint, there's now enough to offset the debt

        // 

        // 14. Vault accrues Goo (receives XYZ GBR in emissions from Gobblers)

        // 15. Bob withdraws XYZ Goo and XYZ Gobblers for XYZ fractions (Admin accrues XYZ Goo as fee)
        // and the protocol admin accrues XYZ Goo in management fees.
        // (performance fee is 10% of the dilution in k beyond kLast)
        // TODO        

        // 16. Alice withdraws XYZ Goo and XYZ Gobblers for XYZ fractions (Admin accrues XYZ Goo as fee)
        // and the protocol admin accrues XYZ Goo in management fees.
        // (performance fee is 10% of the dilution in k beyond kLast)
        // TODO        

    }



        // Scenario:
        // Vault = V, A = Alice, B = Bob
        // 
        // Goober Vault GBR balance = xyz
        // Goober Vault Mult = Σ depositor Gobbler multipliers
        // Goober Vault Goo reserve = Σ depositor Goo balances + Goo emissions + Swap fees accrued
        // Goober Vault Gobblers reserve = Σ depositor Gobbler balances
        // Goober Admin xyz
        // 
        //  ________________________________________________________________________________________
        // | V gbr | V mult | A gbr | A goo | A gbblrs | A mult | B gbr | B goo | B gbblrs | B mult |
        // |========================================================================================|
        // | 1. Alice and Bob have starting balances of 500 Goo and 0 Gobblers                      |
        // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
        // |     0 |      0 |     0 |     0 |        0 |        |     0 |     0 |        0 |      0 |
        // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
        // | 2. Alice adds 500 Goo and mints 2 Gobblers                               |
        // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
        // |     0 |      0 |     0 |   500 |        2 |      0 |     0 |     0 |      500 |      0 |
        // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
        // | 1. Bob adds 1000 Goo and mints 1 Gobbler                  |
        // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
        // |     0 |      0 |     0 |   500 |        2 |      0 |     0 |   XYZ |      XYZ |    XYZ |
        // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
        // | 1. Alice and Bob have a starting balance of 500 Goo and 0 Gobblers                     |
        // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
        // |   XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |   XYZ |   XYZ |      XYZ |    XYZ |
        // |-------|--------|-------|-------|----------|--------|-------|-------|----------|--------|
  

  
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

    // TODO testWithdrawIntegration

    // TODO testSwapIntegration

    // TODO testMintGobblerIntegration (probably can't work with fuzz test)

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

