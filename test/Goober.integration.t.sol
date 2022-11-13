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

// TODO Spot check data table and add FeeTo balance changes marked with "X TODO" (and copy to all following lines, until next change)
// TODO Why swap fee only on Gobblers and not Goo in #9 ? (this is marked with TODO in data table and test code)
// TODO Why no performance fee assessed on withdraw in #15 ? (ditto, this is marked with TODO in data table and test code)

// TODO Bring in LibGOO for actual emission amounts
// TODO Use previewDeposit and previewWithdraw for asserting actual results
// TODO Consider forking mainnet and running against deployed Goo / ArtGobblers contracts
// TODO Consider fuzzing # Gobblers to mint, Goo deposit amounts, Swap params, and time to let Goo accrue
// TODO Refactor test helpers into base class or test utility lib
// TODO Invariants

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
    uint32 internal constant TIME0 = 2_000_000_000;

    // Users
    address internal vault;
    address internal constant alice = address(0xAAAA);
    address internal constant bob = address(0xBBBB);
    address internal constant feeTo = address(0xFFFF1);
    address internal constant minter = address(0xFFFF2);

    // Goo
    uint256 internal aliceGooBalance;
    uint256 internal bobGooBalance;
    uint256 internal vaultGooBalance;

    // Gobblers (in storage to avoid stack too deep)
    uint256 internal aliceGobblerBalance;
    uint256 internal bobGobblerBalance;
    uint256 internal vaultGobblerBalance;
    uint256 internal aliceMult;
    uint256 internal bobMult;
    uint256 internal vaultMult;
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
    uint256 internal totalVaultGooberBalance;
    uint256 internal aliceGooberBalance;
    uint256 internal bobGooberBalance;
    uint256 internal feeToGooberBalance;

    // Vault Accounting
    uint256 internal expectedVaultGooBalance;
    uint256 internal expectedVaultMult;
    uint112 internal expectedVaultGooReserve;
    uint112 internal expectedVaultGobblersReserve;
    uint32 internal expectedVaultLastTimestamp;
    uint32 internal vaultLastTimestamp;

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

    // # Scenario ////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // T = Total, V = Vault, A = Alice, B = Bob, F = FeeTo
    //
    // gbr = Goober vault fractions
    // goo = physically held Goo tokens
    // gbbl = physically held Gobbler NFTs
    // mult = Gobbler multiplier for account
    //
    //  _____________________________________________________________________________________________________________
    // | T gbr | V goo | V gbbl | V mult | A gbr | A goo | A gbbl | A mult | B gbr | B goo | B gbbl | B mult | F gbr |
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
    // | 4. Alice deposits 200 Goo and Gobblers 9 and 8, minting sqrt(17 * 200) GBR Vault fractions                  |
    // | (Alice receives 98%, FeeTo receives 2% as management fee, No performance fee bc there's no growth in k      |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   ~58 |   200 |      2 |    17 |    ~57 |   800 |      1 |      6 |     0 |  1500 |      1 |      9 |X TODO |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 5. Vault accrues Goo for 1 hour, receiving ~sqrt(17 * 200) in emissions                                     |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   ~58 |  ~202 |      2 |    17 |    ~57 |   800 |      1 |      6 |     0 |  1500 |      1 |      9 |  TODO |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 6. Bob swaps in a Gobbler 9 for 500 Goo and a Gobbler 8 out (Vault receives 30 bps in Goo as swap fee)      |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   ~58 |  ~702 |      2 |    18 |    ~57 |   800 |      1 |      6 |     0 |  1500 |      1 |      8 |  TODO |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 7. Vault accrues Goo for 1 hour, receiving ~sqrt(18 * 700) in emissions                                     |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   ~58 |  ~704 |      2 |    18 |    ~57 |   800 |      1 |      6 |     0 |  1500 |      1 |      8 |  TODO |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 8. Vault mints 1 Gobbler for ~59.7 Goo based on VRGDA price (kDebt is recorded)                             |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   ~58 |  ~645 |      3 |    18 |    ~57 |   800 |      1 |      6 |     0 |  1500 |      1 |      8 |  TODO |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 9. Alice swaps in a Gobbler 6 and 30 Goo for a Gobbler 9 out                                                |
    // | (Vault receives 30 bps in Goo on the 3 mult and TODO XYZ Goo as swap fee, Vault does not record kDebt)      |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   ~58 |  ~675 |      3 |    15 |    ~57 |   770 |      1 |      9 |     0 |  1500 |      1 |      8 |  TODO |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 10. Bob deposits 10 Goo, minting him the portion of the total supply by which he increases the value        |
    // | of sqrt(Goo * Mult) as it relates to previous amounts (~1.7 GBR)                                            |
    // | (This triggers a small management fee, but not enough to fully offset the kDebt so no performance fee)      |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   ~60 |  ~685 |      3 |    15 |    ~57 |   770 |      1 |      9 |  ~1.7 |  1490 |      1 |      8 |X TODO |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 11. Gobblers reveal – Vault gets a Gobbler 6, plus ~55 Goo in emissions for the 1 day which elapsed         |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   ~60 |  ~740 |      3 |    21 |    ~57 |   770 |      1 |      9 |  ~1.7 |  1490 |      1 |      8 |  TODO |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 12. Bob deposits 10 more Goo, minting ~2.4 more GBR fractions                                               |
    // | (Between the swap fee and the mint, there's now enough to offset the kDebt so a performance fee is assessed)|
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   ~63 |  ~750 |      3 |    21 |    ~57 |   770 |      1 |      9 |  ~4.1 |  1480 |      1 |      8 |X TODO |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 13. Vault accrues Goo for 1 hour, receiving ~sqrt(18 * 700) in emissions (~2.9 Goo)                         |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   ~63 |  ~753 |      3 |    21 |    ~57 |   770 |      1 |      9 |  ~4.1 |  1480 |      1 |      8 |  TODO |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 14. Bob withdraws 20 Goo in exchange for burning ~2.6 GBR fractions (FeeTo accrues fee in GBR)              |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   ~60 |  ~733 |      3 |    21 |    ~57 |   770 |      1 |      9 |  ~1.5 |  1500 |      1 |      8 |X TODO |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // | 15. Alice withdraws 10 Goo and a Gobbler 6 for ~10.4 GBR fractions (TODO FeeTo accrues fee in GBR)          |
    // |-------|-------|--------|-------|--------|-------|--------|--------|-------|-------|--------|--------|-------|
    // |   ~49 |  ~723 |      2 |    15 |    ~46 |   780 |      2 |     15 |  ~1.5 |  1500 |      1 |      8 |X TODO |
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

        // Check balances
        totalVaultGooberBalance = 0;
        vaultGooBalance = 0;
        vaultGobblerBalance = 0;
        vaultMult = 0;
        aliceGooberBalance = 0;
        aliceGooBalance = 2000 ether;
        aliceGobblerBalance = 0;
        aliceMult = 0;
        bobGooberBalance = 0;
        bobGooBalance = 2000 ether;
        bobGobblerBalance = 0;
        bobMult = 0;
        feeToGooberBalance = 0;
        vaultLastTimestamp = 0;
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);

        // 1. Alice adds 1000 Goo and mints 3 Gobblers
        vm.startPrank(alice);
        gobblers.addGoo(1000 ether);
        aliceGobblers = new uint256[](3);
        aliceGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        aliceGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        aliceGobblers[2] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        // Check balances
        aliceGooberBalance = 0;
        aliceGooBalance = 1000 ether;
        aliceGobblerBalance = 3;
        aliceMult = 0;
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);

        // 2. Bob adds 500 Goo and mints 1 Gobbler
        vm.startPrank(bob);
        gobblers.addGoo(500 ether);
        bobGobblers = new uint256[](1);
        bobGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        // Check balances
        bobGooberBalance = 0;
        bobGooBalance = 1500 ether;
        bobGobblerBalance = 1;
        bobMult = 0;
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);

        // 3. Gobblers reveal – Alice gets a 9, 8, and 6 and Bob gets a Gobbler 9
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(4, "seed");

        // Check reveals
        aliceMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(2)
            + gobblers.getGobblerEmissionMultiple(3);
        bobMult = gobblers.getGobblerEmissionMultiple(4);
        assertEq(gobblers.ownerOf(1), alice);
        assertEq(gobblers.ownerOf(2), alice);
        assertEq(gobblers.ownerOf(3), alice);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        assertEq(gobblers.ownerOf(4), bob);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);

        // 4. Alice deposits 200 Goo and Gobblers 9 and 8, minting sqrt(17 * 200) GBR Vault fractions
        // (Alice receives 98%, FeeTo receives 2% as management fee, No performance fee bc there's no growth in k
        aliceGobblersOnlyTwo = new uint256[](2);
        aliceGobblersOnlyTwo[0] = aliceGobblers[0];
        aliceGobblersOnlyTwo[1] = aliceGobblers[1];
        vm.startPrank(alice);
        uint256 aliceFractions = goober.deposit(aliceGobblersOnlyTwo, 200 ether, alice);
        vm.stopPrank();

        // Check balances
        totalVaultGooberBalance = 58_309_517_948; // ~58 GBR fractions minted total
        vaultGooBalance = 200 ether; // 200 Goo
        vaultGobblerBalance = 2; // 2 Gobblers
        vaultMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(2);
        aliceGooberBalance = aliceFractions;
        aliceGooBalance -= 200 ether;
        aliceGobblerBalance = 1;
        aliceMult = gobblers.getGobblerEmissionMultiple(3);
        feeToGooberBalance = 1_166_190_358; // 2% management fee, No performance fee bc there's no growth in k on initial deposit
        vaultLastTimestamp = TIME0 + 1 days;
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);

        // 5. Vault accrues Goo for 1 hour, receiving ~sqrt(17 * 200) in emissions
        vm.warp(TIME0 + 1 days + 1 hours);

        // Check balances
        totalVaultGooberBalance = 58_309_517_948;
        vaultGooBalance += 2_436_941_761_741_097_378;
        vaultGobblerBalance = 2;
        vaultMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(2);
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);

        // 6. Bob swaps in a Gobbler 9 for 500 Goo and a Gobbler 8 out (Vault receives 30 bps in Goo as swap fee)
        bobSwapIn = new uint256[](1);
        bobSwapIn[0] = 4; // Bob's gobbler
        bobSwapOut = new uint256[](1);
        bobSwapOut[0] = 2; // Alice's 2nd gobbler
        vm.startPrank(bob);

        int256 bobErroneousGoo = goober.previewSwap(bobSwapIn, 0, bobSwapOut, 0);
        assertEq(bobErroneousGoo, -10_959_280_272_307_020_961); // Bob should get ~10.9 Goo back

        goober.swap(bobSwapIn, 0, bobSwapOut, 10 ether, bob, "");
        vm.stopPrank();

        // Check balances
        totalVaultGooberBalance = 58_309_517_948;
        vaultGooBalance -= 10 ether; // 10 less Goo
        vaultGobblerBalance = 2;
        vaultMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(4); // new vault multiple after swap
        bobGooberBalance = 0;
        bobGooBalance = 1510 ether; // 10 more Goo
        bobGobblerBalance = 1;
        bobMult = gobblers.getGobblerEmissionMultiple(2); // new bob multiple after swap
        vaultLastTimestamp = TIME0 + 1 days + 1 hours; // new time
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);

        // 7. Vault accrues Goo for 1 hour, receiving ~sqrt(18 * 700) in emissions
        vm.warp(TIME0 + 1 days + 2 hours);

        // Check balances
        totalVaultGooberBalance = 58_309_517_948;
        vaultGooBalance += 2_460_087_857_714_628_484; // vault receives ~2.4 Goo in emissions
        vaultGobblerBalance = 2;
        vaultMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(4); // new vault multiple after swap
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);

        // 8. Vault mints 1 Gobbler for ~59.7 Goo based on VRGDA price (kDebt is recorded)
        vm.prank(minter);
        goober.mintGobbler();

        // Check balances
        totalVaultGooberBalance = 58_309_517_948;
        vaultGooBalance -= 59_772_562_115_376_111_594; // new balance, after paying ~59.7 Goo to mint
        vaultGobblerBalance = 2;
        vaultLastTimestamp = TIME0 + 1 days + 2 hours; // new time
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);

        // 9. Alice swaps in a Gobbler 6 and 30 Goo for a Gobbler 9 out
        // Vault receives 30 bps in Goo on the 3 mult and TODO XYZ Goo as swap fee, Vault does not record kDebt)
        aliceSwapIn = new uint256[](1);
        aliceSwapIn[0] = 3; // Alice's Gobbler 6
        aliceSwapOut = new uint256[](1);
        aliceSwapOut[0] = 4; // Bob's Gobbler 9

        int256 aliceErroneousGoo = goober.previewSwap(aliceSwapIn, 0, aliceSwapOut, 0);
        assertEq(aliceErroneousGoo, 27_301_611_343_663_367_346); // Alice will need to swap in at least ~27.3 Goo

        vm.startPrank(alice);
        goober.swap(aliceSwapIn, 30 ether, aliceSwapOut, 0, alice, "");
        vm.stopPrank();

        // Check balances
        totalVaultGooberBalance = 58_309_517_948;
        vaultGooBalance += 30 ether; // new balance, after alice swaps in 30 Goo
        vaultGobblerBalance = 2;
        vaultMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(3); // new multiple after swap
        aliceGooberBalance = aliceFractions;
        aliceGooBalance -= 30 ether; // alice swaps in 30 Goo
        aliceGobblerBalance = 1;
        aliceMult = gobblers.getGobblerEmissionMultiple(4); // new multiple after swap
        vaultLastTimestamp = TIME0 + 1 days + 2 hours;
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);

        // 10. Bob deposits 10 Goo, minting him the portion of the total supply by which he increases the value
        // of sqrt(Goo * Mult) as it relates to previous amounts
        // (This triggers a small fee, but not enough to fully offset the kDebt so no performance fee)
        vm.prank(bob);
        emptyGobblers = new uint256[](0);
        uint256 bobFractions = goober.deposit(emptyGobblers, 10 ether, bob);

        // Check balances
        totalVaultGooberBalance += 1_739_671_538; // ~1.7 more GBR fractions minted
        vaultGooBalance += 10 ether; // bob deposits 10 Goo
        vaultGobblerBalance = 2;
        vaultMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(3);
        bobGooberBalance = bobFractions;
        bobGooBalance -= 10 ether; // 10 less Goo
        bobGobblerBalance = 1;
        bobMult = gobblers.getGobblerEmissionMultiple(2);
        feeToGooberBalance += 34_793_430; // Small management fee
        vaultLastTimestamp = TIME0 + 1 days + 2 hours;
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);

        // 11. Gobblers reveal – Vault gets a Gobbler 6, plus ~55 Goo in emissions for the 1 day which elapsed
        vm.warp(TIME0 + 1 days + 2 hours + 1 days);
        _setRandomnessAndReveal(1, "seed2");

        // Check balances
        totalVaultGooberBalance = 60_049_189_486;
        vaultGooBalance += 55_002_970_768_153_471_144; // Goo emissions
        vaultGobblerBalance = 2;
        vaultMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(3)
            + gobblers.getGobblerEmissionMultiple(5); // new multiple
        feeToGooberBalance = 1_200_983_788;
        vaultLastTimestamp = TIME0 + 1 days + 2 hours;
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);

        // 12. Bob deposits 10 more Goo
        // (Between the swap fee and the mint, there's now enough to offset the kDebt so a performance fee is assessed)
        vm.prank(bob);
        bobFractions += goober.deposit(emptyGobblers, 10 ether, bob);

        // Check balances
        totalVaultGooberBalance += 2_400_586_916; // ~2.4 more fractions minted
        vaultGooBalance += 10 ether; // 10 more Goo from Bob
        vaultGobblerBalance = 2;
        vaultMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(3)
            + gobblers.getGobblerEmissionMultiple(5); // new multiple
        bobGooberBalance = bobFractions; // Bob is only minted ~2 GBR fractions, after performance fee is assessed
        bobGooBalance -= 10 ether; // 10 less Goo
        bobGobblerBalance = 1;
        bobMult = gobblers.getGobblerEmissionMultiple(2);
        feeToGooberBalance += 1_112_696_324; // 10% performance fee assessed
        vaultLastTimestamp = TIME0 + 1 days + 2 hours + 1 days; // new time
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);

        // 13. Vault accrues Goo for 1 hour, receiving ~sqrt(18 * 700) in emissions
        vm.warp(TIME0 + 1 days + 2 hours + 1 days + 1 hours);

        // Check balances
        totalVaultGooberBalance = 62_449_776_402;
        vaultGooBalance += 2_967_939_719_600_851_528; // ~2.9 Goo in emissions
        vaultGobblerBalance = 2;
        vaultMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(3)
            + gobblers.getGobblerEmissionMultiple(5);
        feeToGooberBalance = 2_313_680_112;
        vaultLastTimestamp = TIME0 + 1 days + 2 hours + 1 days;
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);

        // 14. Bob withdraws 20 Goo in exchange for burning 2_587_213_346 GBR fractions (FeeTo accrues fee in GBR)
        vm.prank(bob);
        uint256 fractionsWithdrawn = goober.withdraw(emptyGobblers, 20 ether, bob, bob);

        // Check balances
        totalVaultGooberBalance -= 2_587_213_346; // less total supply of GBR fractions
        vaultGooBalance -= 20 ether; // 20 less Goo
        vaultGobblerBalance = 2;
        vaultMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(3)
            + gobblers.getGobblerEmissionMultiple(5);
        bobGooberBalance -= fractionsWithdrawn; // less 2_587_213_346 GBR
        bobGooBalance += 20 ether; // 20 more Goo
        bobGobblerBalance = 1;
        bobMult = gobblers.getGobblerEmissionMultiple(2);
        feeToGooberBalance += 38_474_980; // fee assessed
        vaultLastTimestamp = TIME0 + 1 days + 2 hours + 1 days + 1 hours; // new time
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);

        // TODO why no performance fee assessed on this one ?
        // 15. Alice withdraws 10 Goo and a Gobbler 6 for 10_416_352_000 GBR fractions (FeeTo accrues fee in GBR)
        vm.prank(alice);
        aliceWithdraw = new uint256[](1);
        aliceWithdraw[0] = 3; // Alice's Gobbler 6
        fractionsWithdrawn = goober.withdraw(aliceWithdraw, 10 ether, alice, alice);

        // Check balances
        totalVaultGooberBalance -= 10_416_352_000; // less total supply of GBR fractions
        vaultGooBalance -= 10 ether; // 10 less Goo
        vaultGobblerBalance = 1; // new balance
        vaultMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(5); // new multiple
        aliceGooberBalance -= fractionsWithdrawn; // 10_416_352_000 less GBR
        aliceGooBalance += 10 ether; // 10 more Goo
        aliceGobblerBalance = 2; // new balance
        aliceMult = gobblers.getGobblerEmissionMultiple(4) + gobblers.getGobblerEmissionMultiple(3); // new multiple
        feeToGooberBalance = 2_352_155_092;
        vaultLastTimestamp = TIME0 + 1 days + 2 hours + 1 days + 1 hours;
        // Vault
        assertEq(goober.totalSupply(), totalVaultGooberBalance);
        (expectedVaultGooBalance, expectedVaultMult) = goober.totalAssets();
        assertEq(expectedVaultGooBalance, vaultGooBalance);
        assertEq(expectedVaultMult, vaultMult);
        (expectedVaultGooReserve, expectedVaultGobblersReserve, expectedVaultLastTimestamp) = goober.getReserves();
        assertEq(expectedVaultGooReserve, vaultGooBalance);
        assertEq(expectedVaultGobblersReserve, vaultMult);
        assertEq(expectedVaultLastTimestamp, vaultLastTimestamp);
        // Alice
        assertEq(goober.balanceOf(alice), aliceGooberBalance);
        assertEq(goo.balanceOf(alice), aliceGooBalance);
        assertEq(gobblers.balanceOf(alice), aliceGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(alice), aliceMult);
        // Bob
        assertEq(goober.balanceOf(bob), bobGooberBalance);
        assertEq(goo.balanceOf(bob), bobGooBalance);
        assertEq(gobblers.balanceOf(bob), bobGobblerBalance);
        assertEq(gobblers.getUserEmissionMultiple(bob), bobMult);
        // FeeTo
        assertEq(goober.balanceOf(feeTo), feeToGooberBalance);
    }

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
