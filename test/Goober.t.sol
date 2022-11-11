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

// DONE write tests for flagGobbler
// DONE write tests for IERC721Receiver
// TODO write event tests
// TODO write tests for single/multiple deposit, withdraw, swap happy paths
// TODO write tests to cover all require cases, then refactor into custom errors
// TODO write fuzz tests that use actors, with various assets and actions
// DONE write helper function for test fixture setup
// DONE refactor out K calculations into internal methods
// DONE refactor actor setup text fixture
// DONE clean up all ether, replace with scaling constant

contract GooberTest is Test {
    using stdStorage for StdStorage;

    Goober internal goober;

    Utilities internal utils;
    address payable[] internal users;
    address internal constant FEE_TO = address(0xFEEE);
    address internal constant MINTER = address(0x1337);
    address internal constant OTHER = address(0xDEAD);

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

    uint256 internal constant START_BAL = 2000 ether;
    uint256 internal constant TIME0 = 2_000_000_000; // now-ish unix timestamp

    function setUp() public {
        vm.warp(TIME0);

        utils = new Utilities();
        users = utils.createUsers(11);
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
            _merkleRoot: keccak256(abi.encodePacked(users[0])),
            _mintStart: TIME0,
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
            _mintStart: TIME0,
            _goo: goo,
            _community: address(0xBEEF),
            _artGobblers: gobblers,
            _baseUri: ""
        });

        // Deploy Goober
        goober = new Goober({
            _gobblersAddress: address(gobblers),
            _gooAddress: address(goo),
            _feeTo: FEE_TO,
            _minter: MINTER
        });

        // Setup balances and approvals
        for (uint256 i = 1; i < 11; i++) {
            _writeTokenBalance(users[i], address(goo), START_BAL);

            vm.startPrank(users[i]);
            goo.approve(address(goober), type(uint256).max);
            gobblers.setApprovalForAll(address(goober), true);
            vm.stopPrank();
        }
    }

    function testInitial() public {
        assertEq(goober.name(), "Goober");
        assertEq(goober.symbol(), "GBR");
        assertEq(goober.decimals(), 18);

        assertEq(address(goober.goo()), address(goo));
        assertEq(address(goober.artGobblers()), address(gobblers));

        assertEq(goober.feeTo(), FEE_TO);
        assertEq(goober.minter(), MINTER);
    }

    function testSetRandomnessAndRevealHelper() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        gobblers.mintFromGoo(100 ether, true);
        gobblers.mintFromGoo(100 ether, true);
        gobblers.mintFromGoo(100 ether, true);

        // Reveal 3 at once
        vm.warp(TIME0 + 1 days);

        _setRandomnessAndReveal(3, "seed");

        assertEq(gobblers.getGobblerEmissionMultiple(1), 9);
        assertEq(gobblers.getGobblerEmissionMultiple(2), 8);
        assertEq(gobblers.getGobblerEmissionMultiple(3), 6);

        // Reveal one at a time
        gobblers.addGoo(500 ether);
        gobblers.mintFromGoo(100 ether, true);
        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "seed");
        assertEq(gobblers.getGobblerEmissionMultiple(1), 9);

        gobblers.addGoo(500 ether);
        gobblers.mintFromGoo(100 ether, true);
        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "seed");
        assertEq(gobblers.getGobblerEmissionMultiple(1), 9);

        gobblers.addGoo(500 ether);
        gobblers.mintFromGoo(100 ether, true);
        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "seed");
        assertEq(gobblers.getGobblerEmissionMultiple(1), 9);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
    // Deposit
    //////////////////////////////////////////////////////////////*/

    // Get reserve balances before they are updated
    // Assess performance fee since last tx
    // Transfer any Goo or Gobblers IN (before minting to prevent ERC777 reentrancy) TODO add test
    // Get reserve balances again
    // Mint fractions to depositor (less management fee)
    // Update reserve balances
    // Emit event

    function testDepositBoth() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);

        uint256 gooToDeposit = 200 ether;

        // Precondition checks
        // Goo ownership
        uint256 userGooBalance = gobblers.gooBalance(users[1]);
        assertEq(gobblers.gooBalance(address(goober)), 0);
        // Gobbler ownership
        assertEq(gobblers.ownerOf(artGobblers[0]), users[1]);
        assertEq(gobblers.ownerOf(artGobblers[1]), users[1]);
        // Fractions of depositor
        assertEq(goober.balanceOf(users[1]), 0);
        // Total assets and Reserve balances
        (uint256 gooTokens, uint256 gobblerMult) = goober.totalAssets();
        assertEq(gooTokens, 0);
        assertEq(gobblerMult, 0);
        (uint112 gooReserve, uint112 gobblerReserve, uint32 blockTimestampLast) = goober.getReserves();
        assertEq(gooReserve, 0);
        assertEq(gobblerReserve, 0);
        assertEq(blockTimestampLast, 0);

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // TODO fix event tests
        // Check Deposit event
        // vm.expectEmit(true, true, true, false);
        // emit Deposit(users[1], users[1], artGobblers, gooToDeposit, 0);

        // Check FeesAccrued events
        // vm.expectEmit(true, true, true, false);
        // emit FeesAccrued(FEE_TO, 0, true, 0); // no performance fee assessed
        // vm.expectEmit(true, true, true, false);
        // emit FeesAccrued(FEE_TO, 0, false, 0); // management fee

        // Deposit 2 gobblers and 200 goo
        uint256 fractions = goober.deposit(artGobblers, gooToDeposit, users[1]);
        vm.stopPrank();

        // Goo is transferred into vault
        assertEq(gobblers.gooBalance(users[1]), userGooBalance); // no change
        assertEq(gobblers.gooBalance(address(goober)), gooToDeposit);

        // Gobblers are transferred into vault
        assertEq(gobblers.ownerOf(artGobblers[0]), address(goober));
        assertEq(gobblers.ownerOf(artGobblers[1]), address(goober));

        // Fractions are minted to depositor
        assertEq(goober.balanceOf(users[1]), fractions);

        // Reserve balances and total assets are updated
        uint256 expectedGobblerMult = gobblers.getGobblerEmissionMultiple(1) + gobblers.getGobblerEmissionMultiple(2);
        (uint256 gooTokensAfter, uint256 gobblerMultAfter) = goober.totalAssets();
        assertEq(gooTokensAfter, gooToDeposit);
        assertEq(gobblerMultAfter, expectedGobblerMult);
        (uint112 gooReserveAfter, uint112 gobblerReserveAfter, uint32 blockTimestampLastAfter) = goober.getReserves();
        assertEq(gooReserveAfter, gooToDeposit);
        assertEq(gobblerReserveAfter, expectedGobblerMult);
        assertEq(blockTimestampLastAfter, TIME0 + 1 days);
    }

    // function testDepositWhenOnlyGoo() public {

    // }

    // function testDepositWhenOnlyGobblers() public {

    // }

    function testEventDeposit() public {
      // Add Goo and mint Gobblers
      vm.startPrank(users[1]);
      uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);

      uint256 gooToDeposit = 200 ether;

      // Precondition checks
      // Goo ownership
      uint256 userGooBalance = gobblers.gooBalance(users[1]);
      assertEq(gobblers.gooBalance(address(goober)), 0);
      // Gobbler ownership
      assertEq(gobblers.ownerOf(artGobblers[0]), users[1]);
      assertEq(gobblers.ownerOf(artGobblers[1]), users[1]);
      // Fractions of depositor
      assertEq(goober.balanceOf(users[1]), 0);
      // Total assets and Reserve balances
      (uint256 gooTokens, uint256 gobblerMult) = goober.totalAssets();
      assertEq(gooTokens, 0);
      assertEq(gobblerMult, 0);
      (uint112 gooReserve, uint112 gobblerReserve, uint32 blockTimestampLast) = goober.getReserves();
      assertEq(gooReserve, 0);
      assertEq(gobblerReserve, 0);
      assertEq(blockTimestampLast, 0);

      // Reveal
      vm.warp(TIME0 + 1 days);
      _setRandomnessAndReveal(2, "seed");

      // Check Deposit event
      vm.expectEmit(true, true, false, true, address(goober));
      emit Deposit(users[1], users[1], artGobblers, gooToDeposit, 57143327590);

      // TODO
      // Check FeesAccrued events
      // (uint112 _gooBalance, uint112 _gobblerBalanceMult,) = goober.getReserves();
      // (uint256 fee, uint112 kDebtChange, uint256 deltaK) = goober._previewPerformanceFee(_gooBalance, _gobblerBalanceMult);
      // assertEq(fee,0);
      // assertEq(deltaK,0);
      // vm.expectEmit(true, false, false, true, address(goober));
      // emit FeesAccrued(FEE_TO, 0, true, 0); // no performance fee assessed

      // vm.expectEmit(true, false, false, true, address(goober));
      // emit FeesAccrued(FEE_TO, 57143327590, false, 0); // management fee

      // event FeesAccrued(address indexed feeTo, uint256 fractions, bool performanceFee, uint256 _deltaK);


      // Deposit 2 gobblers and 200 goo
      uint256 fractions = goober.deposit(artGobblers, gooToDeposit, users[1]);
      vm.stopPrank();

      assertEq(fractions,57143327590);

    }

    // function testRevertDepositWhenInsufficientLiquidityMined() public {
    //     // Goober: INSUFFICIENT_LIQUIDITY_MINTED
    // }

    function testSafeDeposit() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblers, gooToDeposit);

        uint256 fractions = goober.safeDeposit(artGobblers, gooToDeposit, users[1], expectedFractions, block.timestamp);
        vm.stopPrank();

        // Fractions minted matches the expected amount
        assertEq(fractions, expectedFractions);
    }

    function testSafeDepositFailsWhenExpired() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblers, gooToDeposit);

        vm.expectRevert("Goober: EXPIRED");

        goober.safeDeposit(artGobblers, gooToDeposit, users[1], expectedFractions, block.timestamp - 1);
    }

    function testSafeDepositFailsWhenInsufficientLiquidityMinted() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblers, gooToDeposit);

        vm.expectRevert("Goober: INSUFFICIENT_LIQUIDITY_MINTED");

        goober.safeDeposit(artGobblers, gooToDeposit, users[1], expectedFractions + 1, block.timestamp + 1);
    }

    /*//////////////////////////////////////////////////////////////
    // Withdraw
    //////////////////////////////////////////////////////////////*/

    // Get reserves
    // Assess performance fee since last tx
    // Transfer Goo and Gobblers OUT, if any
    // Get reserves again
    // Calculate multiplier
    // Check multipler and Goo both greater than 0
    // Calculate fractions, Check some liquidity will be left over
    // Check approvals, if withdrawing on behalf of someone else
    // Burn fractions from owner
    // Update reserves
    // Emit event

    function testWithdrawBoth() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersHold = new uint256[](1);
        uint256[] memory artGobblersToWithdraw = new uint256[](1);

        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersHold[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblersToWithdraw[0] = artGobblers[0];

        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(3, "seed");

        /*uint256 fractions = */
        goober.deposit(artGobblers, 500 ether, users[1]);

        // TODO

        vm.warp(block.timestamp + 7 days);

        goober.withdraw(artGobblersToWithdraw, 10 ether, users[1], users[1]);

        // TODO
    }

    // function testWithdrawWhenDepositedOnlyGoo() public {}

    // function testWithdrawWhenDepositedOnlyGobblers() public {}

    function testRevertWithdrawWhenOwnerIsNotReceiver() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        vm.startPrank(users[2]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers2 = new uint256[](1);
        artGobblers2[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        vm.prank(users[1]);
        goober.deposit(artGobblers, 200 ether, users[1]);

        vm.startPrank(users[2]);
        uint256 fractions = goober.deposit(artGobblers2, 200 ether, users[2]);
        goober.approve(OTHER, 1); // not the right amount
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);

        vm.expectRevert(IGoober.InsufficientAllowance.selector);

        vm.prank(OTHER);
        goober.withdraw(artGobblers2, fractions, users[2], users[2]);
    }

    function testWithdrawWhenOwnerIsNotReceiverButWithSufficientAllowance() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        vm.startPrank(users[2]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers2 = new uint256[](1);
        artGobblers2[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        vm.prank(users[1]);
        goober.deposit(artGobblers, 200 ether, users[1]);

        vm.startPrank(users[2]);
        uint256 fractions = goober.deposit(artGobblers2, 200 ether, users[2]);
        goober.approve(OTHER, type(uint256).max);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);

        // Other account with sufficient allowance can withdraw

        vm.prank(OTHER);
        goober.withdraw(artGobblers2, fractions, users[2], users[2]);
    }

    function testWithdrawWhenOwnerIsNotReceiverButWithSufficientAllowanceThatIsNotMax() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        vm.startPrank(users[2]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers2 = new uint256[](1);
        artGobblers2[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        vm.prank(users[1]);
        goober.deposit(artGobblers, 200 ether, users[1]);

        vm.startPrank(users[2]);
        uint256 fractions = goober.deposit(artGobblers2, 200 ether, users[2]);
        goober.approve(OTHER, type(uint256).max - 1);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);

        // Other account with sufficient allowance can withdraw

        vm.prank(OTHER);
        goober.withdraw(artGobblers2, fractions, users[2], users[2]);
    }

    // test withdraw when owner != receiver

    function testEventWithdraw() public {
      // Add Goo and mint Gobblers
      vm.startPrank(users[1]);
      uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);
      uint256[] memory artGobblersToWithdraw = new uint256[](1);

      artGobblersToWithdraw[0] = artGobblers[0];

      uint256 gooToDeposit = 200 ether;

      // Reveal
      vm.warp(TIME0 + 1 days);
      _setRandomnessAndReveal(2, "seed");

      // Deposit 2 gobblers and 200 goo
      uint256 expectedFractionsOut = goober.previewDeposit(artGobblers, gooToDeposit);

      goober.safeDeposit(artGobblers, gooToDeposit, users[1], expectedFractionsOut, block.timestamp + 1);

      vm.warp(block.timestamp + 7 days);

      uint256 userGooBefore = goo.balanceOf(users[1]);
      uint256 gooToWithdraw = 10 ether;

      uint256 expectedFractionsIn = goober.previewWithdraw(artGobblersToWithdraw, gooToWithdraw);

      assertEq(goober.balanceOf(users[1]),expectedFractionsOut);

      vm.expectEmit(true, true, true, true, address(goober));
      emit Withdraw(users[1],users[1],users[1], artGobblersToWithdraw, gooToWithdraw, expectedFractionsIn);

      uint256 fractionsIn = goober.safeWithdraw(
          artGobblersToWithdraw, gooToWithdraw, users[1], users[1], expectedFractionsIn, block.timestamp + 1
      );

      assertEq(fractionsIn, expectedFractionsIn);

      uint256 userGooAfter = goo.balanceOf(users[1]);

      // The users GOO balance should have changed by the same amount as gooToWithdraw.
      assertEq(userGooAfter - userGooBefore, gooToWithdraw);

      // The owner of the Gobbler should now be the user again.
      assertEq(gobblers.ownerOf(artGobblersToWithdraw[0]), users[1]);
      vm.stopPrank();

    }

    // Goober: INSUFFICIENT LIQUIDITY WITHDRAW edge cases

    // TODO getting std Arithmetic over/underflow revert before Goober revert
    // function testRevertDepositWhenGooBalanceWouldOverflowUint112() public {
    //     _writeTokenBalance(users[10], address(goo), type(uint128).max);

    //     vm.startPrank(users[10]);
    //     uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 1);

    //     vm.warp(TIME0 + 1 days);
    //     _setRandomnessAndReveal(1, "seed");

    //     vm.expectRevert("Goober: OVERFLOW");

    //     goober.deposit(artGobblers, type(uint112).max + 1, users[10]);
    // }

    function testRevertWithdrawWhenInsufficientGobblerMult() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersHold = new uint256[](1);

        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersHold[0] = gobblers.mintFromGoo(100 ether, true);

        vm.warp(block.timestamp + 1 days);

        _setRandomnessAndReveal(3, "seed");

        goober.deposit(artGobblers, 500 ether, users[1]);

        vm.expectRevert(IGoober.MustLeaveLiquidity.selector);

        goober.withdraw(new uint256[](0), 500 ether, users[1], users[1]);
    }

    // function testRevertWithdrawWhenWithdrawingLastGoo() public {

    // }

    function testRevertWithdrawWhenWithdrawingLastGobbler() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersHold = new uint256[](1);

        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersHold[0] = gobblers.mintFromGoo(100 ether, true);

        vm.warp(block.timestamp + 1 days);

        _setRandomnessAndReveal(3, "seed");

        goober.deposit(artGobblers, 500 ether, users[1]);

        vm.expectRevert(IGoober.MustLeaveLiquidity.selector);

        goober.withdraw(artGobblers, 10 ether, users[1], users[1]);
    }

    function testWithdraw() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);
        uint256[] memory artGobblersToWithdraw = new uint256[](1);

        artGobblersToWithdraw[0] = artGobblers[0];

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractionsOut = goober.previewDeposit(artGobblers, gooToDeposit);

        goober.safeDeposit(artGobblers, gooToDeposit, users[1], expectedFractionsOut, block.timestamp + 1);

        vm.warp(block.timestamp + 7 days);

        uint256 userGooBefore = goo.balanceOf(users[1]);
        uint256 gooToWithdraw = 10 ether;

        uint256 expectedFractionsIn = goober.previewWithdraw(artGobblersToWithdraw, gooToWithdraw);

        uint256 fractionsIn = goober.safeWithdraw(
            artGobblersToWithdraw, gooToWithdraw, users[1], users[1], expectedFractionsIn, block.timestamp + 1
        );

        assertEq(fractionsIn, expectedFractionsIn);

        uint256 userGooAfter = goo.balanceOf(users[1]);

        // The users GOO balance should have changed by the same amount as gooToWithdraw.
        assertEq(userGooAfter - userGooBefore, gooToWithdraw);

        // The owner of the Gobbler should now be the user again.
        assertEq(gobblers.ownerOf(artGobblersToWithdraw[0]), users[1]);

        vm.stopPrank();
    }

    function testWithdrawReventsWhenExpired() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);
        uint256[] memory artGobblersToWithdraw = new uint256[](1);

        artGobblersToWithdraw[0] = artGobblers[0];

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractionsOut = goober.previewDeposit(artGobblers, gooToDeposit);

        goober.safeDeposit(artGobblers, gooToDeposit, users[1], expectedFractionsOut, block.timestamp + 1);

        vm.warp(block.timestamp + 7 days);

        uint256 gooToWithdraw = 10 ether;

        uint256 expectedFractionsIn = goober.previewWithdraw(artGobblersToWithdraw, gooToWithdraw);

        vm.expectRevert("Goober: EXPIRED");

        goober.safeWithdraw(
            artGobblersToWithdraw, gooToWithdraw, users[1], users[1], expectedFractionsIn, block.timestamp - 1
        );
    }

    function testWithdrawRevertsWhenFractionsBurnedExceedsLimit() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);
        uint256[] memory artGobblersToWithdraw = new uint256[](1);

        artGobblersToWithdraw[0] = artGobblers[0];

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractionsOut = goober.previewDeposit(artGobblers, gooToDeposit);

        goober.safeDeposit(artGobblers, gooToDeposit, users[1], expectedFractionsOut, block.timestamp + 1);

        vm.warp(block.timestamp + 7 days);

        uint256 gooToWithdraw = 10 ether;

        uint256 expectedFractionsIn = goober.previewWithdraw(artGobblersToWithdraw, gooToWithdraw);

        vm.expectRevert("Goober: BURN_ABOVE_LIMIT");

        goober.safeWithdraw(
            artGobblersToWithdraw, gooToWithdraw, users[1], users[1], expectedFractionsIn - 1, block.timestamp + 1
        );
    }

    // Goober: INSUFFICIENT_ALLOWANCE

    /*//////////////////////////////////////////////////////////////
    // Swap
    //////////////////////////////////////////////////////////////*/

    // Check at least some Goo or Gobblers are being swapped out
    // Get reserves
    // Check receiver address is not Goo nor Gobbler
    // Transfer any Goo or Gobblers to correct out addresses
    // If flash loan, call flash loan
    // Transfer any Goo or Gobblers IN
    // Get reserves again
    // Calculate amounts in — did we get more in than we got out? good, otherwise bad
    // Check at least some Goo or Gobblers are being swapped in
    // Check growth of k
    // Assess performance fee on growth of k
    // Update reserves
    // Emit event

    function testSwap() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);

        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        uint256[] memory artGobblersThree = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblersThree[0] = artGobblers[0];

        vm.warp(block.timestamp + 1 days);

        _setRandomnessAndReveal(3, "seed");

        uint256 gooTokens = 200 ether;
        uint256 fractions = goober.deposit(artGobblers, gooTokens, users[1]);

        // TODO

        bytes memory data;
        IGoober.SwapParams memory swap =
            IGoober.SwapParams(artGobblersThree, 0 ether, artGobblersTwo, 100 ether, users[1], data);
        goober.swap(swap);

        fractions = goober.withdraw(artGobblersTwo, 100 ether, users[1], users[1]);

        // TODO assertions
    }

    // Goober: INSUFFICIENT_OUTPUT_AMOUNT

    // Goober: INVALID_TO

    // Goober: INSUFFICIENT_INPUT_AMOUNT

    function testSafeSwap() public {
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 4);

        uint256[] memory artGobblersToDeposit = new uint256[](3);
        artGobblersToDeposit[0] = artGobblers[0];
        artGobblersToDeposit[1] = artGobblers[1];
        artGobblersToDeposit[2] = artGobblers[2];

        uint256[] memory artGobblersToSwap = new uint256[](1);
        artGobblersToSwap[0] = artGobblers[3];

        uint256[] memory artGobblersOut = new uint256[](1);
        artGobblersOut[0] = artGobblers[0];

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(4, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblersToDeposit, gooToDeposit);

        goober.safeDeposit(artGobblersToDeposit, gooToDeposit, users[1], expectedFractions, block.timestamp);

        bytes memory data;
        IGoober.SwapParams memory swap =
            IGoober.SwapParams(artGobblersOut, 0, artGobblersToSwap, 235765844523515264, users[1], data);

        int256 expectedErroneousGoo = goober.previewSwap(artGobblersToSwap, 235765844523515264, artGobblersOut, 0);

        int256 erroneousGoo = goober.safeSwap(swap, 0, block.timestamp + 1);

        assertEq(expectedErroneousGoo, erroneousGoo);

        vm.stopPrank();
    }

    function testSafeSwapRevertsWhenExpired() public {
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 4);

        uint256[] memory artGobblersToDeposit = new uint256[](3);
        artGobblersToDeposit[0] = artGobblers[0];
        artGobblersToDeposit[1] = artGobblers[1];
        artGobblersToDeposit[2] = artGobblers[2];

        uint256[] memory artGobblersToSwap = new uint256[](1);
        artGobblersToSwap[0] = artGobblers[3];

        uint256[] memory artGobblersOut = new uint256[](1);
        artGobblersOut[0] = artGobblers[0];

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(4, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblersToDeposit, gooToDeposit);

        goober.safeDeposit(artGobblersToDeposit, gooToDeposit, users[1], expectedFractions, block.timestamp);

        bytes memory data;
        IGoober.SwapParams memory swap =
            IGoober.SwapParams(artGobblersOut, 0, artGobblersToSwap, 235765844523515264, users[1], data);

        vm.expectRevert("Goober: EXPIRED");

        goober.safeSwap(swap, 0, block.timestamp - 1);
    }

    function testSafeSwapRevertsWhenErroneousGooIsTooLarge() public {
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 4);

        uint256[] memory artGobblersToDeposit = new uint256[](3);
        artGobblersToDeposit[0] = artGobblers[0];
        artGobblersToDeposit[1] = artGobblers[1];
        artGobblersToDeposit[2] = artGobblers[2];

        uint256[] memory artGobblersToSwap = new uint256[](1);
        artGobblersToSwap[0] = artGobblers[3];

        uint256[] memory artGobblersOut = new uint256[](1);
        artGobblersOut[0] = artGobblers[0];

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(4, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblersToDeposit, gooToDeposit);

        goober.safeDeposit(artGobblersToDeposit, gooToDeposit, users[1], expectedFractions, block.timestamp);

        bytes memory data;
        IGoober.SwapParams memory swap =
            IGoober.SwapParams(artGobblersOut, 0, artGobblersToSwap, 235765844523515265, users[1], data);

        vm.expectRevert("Goober: SWAP_EXCEEDS_ERRONEOUS_GOO");

        goober.safeSwap(swap, 0, block.timestamp + 1);
    }

    /*//////////////////////////////////////////////////////////////
    // Accounting
    //////////////////////////////////////////////////////////////*/

    function testTotalAssets() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](1);
        uint256[] memory artGobblersTwo = new uint256[](1);
        uint256[] memory artGobblersThree = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblersThree[0] = gobblers.mintFromGoo(100 ether, true);

        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(3, "seed");

        uint256 expectedGooTokens = 300 ether;
        uint256 expectedGobblerMult = gobblers.getUserEmissionMultiple(users[1]);

        goober.deposit(artGobblers, 100 ether, users[1]);
        goober.deposit(artGobblersTwo, 100 ether, users[1]);
        goober.deposit(artGobblersThree, 100 ether, users[1]);

        (uint256 actualGooTokens, uint256 actualGobblerMult) = goober.totalAssets();
        assertEq(actualGooTokens, expectedGooTokens);
        assertEq(actualGobblerMult, expectedGobblerMult);
    }

    // getReserves
    // convertToFractions
    // convertToAssets

    function testPreviewDeposit() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        // Test first deposit
        uint256[] memory artGobblers = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(1, "seed");
        uint256 expected = goober.previewDeposit(artGobblers, 100 ether);
        uint256 actual = goober.deposit(artGobblers, 100 ether, users[1]);
        assertEq(expected, actual);
        // Test second deposit
        uint256[] memory artGobblersTwo = new uint256[](1);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "seed");
        expected = goober.previewDeposit(artGobblersTwo, 100 ether);
        actual = goober.deposit(artGobblersTwo, 100 ether, users[1]);
        assertEq(expected, actual);
    }

    function testPreviewWithdraw() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](1);
        uint256[] memory artGobblersTwo = new uint256[](1);
        uint256[] memory artGobblersThree = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblersThree[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(3, "seed");
        goober.deposit(artGobblers, 100 ether, users[1]);
        goober.deposit(artGobblersTwo, 100 ether, users[1]);
        goober.deposit(artGobblersThree, 100 ether, users[1]);
        uint256 expected = goober.previewWithdraw(artGobblersThree, 100 ether);
        uint256 actual = goober.withdraw(artGobblersThree, 100 ether, users[1], users[1]);
        expected = goober.previewWithdraw(artGobblersTwo, 100 ether);
        actual = goober.withdraw(artGobblersTwo, 100 ether, users[1], users[1]);
        assertEq(expected, actual);
    }

    function testPreviewSwap() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory gobblersOut = new uint256[](1);
        gobblersOut[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "1");

        vm.startPrank(users[2]);
        gobblers.addGoo(500 ether);
        uint256[] memory gobblersIn = new uint256[](1);
        gobblersIn[0] = gobblers.mintFromGoo(100 ether, true);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(1, "1");

        vm.startPrank(users[1]);
        goober.deposit(gobblersOut, 100 ether, users[1]);
        vm.stopPrank();

        uint256 gooIn = 301808132521938937;
        uint256 gooOut = 0 ether;

        // TODO(Fix preview and swap erroneous goo)
        // You'd think it'd be 300902708124373119, but, you need to pay 30 bps
        // on the 30 bps, etc and its 301808432424373119. This has some imprecision at the 9th decimal to fix
        int256 expectedAdditionalGooRequired = 301808132521938937;
        int256 previewAdditionalGooRequired = goober.previewSwap(gobblersIn, 0, gobblersOut, gooOut);
        // TODO(Fix imprecision in swap function)
        assertEq(previewAdditionalGooRequired, expectedAdditionalGooRequired);
        vm.startPrank(users[2]);
        bytes memory data;
        IGoober.SwapParams memory swap = IGoober.SwapParams(gobblersOut, gooOut, gobblersIn, gooIn, users[2], data);
        int256 erroneousGoo = goober.swap(swap);
        assertEq(erroneousGoo, int256(0));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
    // Mint Gobbler
    //////////////////////////////////////////////////////////////*/

    function testMint() public {
        // Safety check to verify starting gobblerPrice is correct.
        assertEq(gobblers.gobblerPrice(), 73013654753028651285);

        // Add enough Goo to vault to mint a single Gobbler.
        _writeTokenBalance(users[10], address(goo), 1000 ether);

        // Mint the first gobbler
        vm.startPrank(users[10]);
        uint256[] memory artGobbler = new uint256[](1);
        artGobbler[0] = gobblers.mintFromGoo(75 ether, false);
        // Check to see we own the first Gobbler.
        assertEq(gobblers.ownerOf(1), users[10]);
        // Warp a day ahead until we can reveal Gobbler 1.
        vm.warp(block.timestamp + 86400);
        _setRandomnessAndReveal(1, "seed");
        uint256 gobblerMult = (gobblers.getGobblerEmissionMultiple(artGobbler[0]));
        // Based on our seed, we get a mult of 9 here.
        assertEq(gobblerMult, 9);

        // Pool is setup by depositing 1 gobbler and 81 goo.
        // We do this after warp to not accrue extra goo.
        // Depositing automatically makes the goo virtual.
        uint256 gooTokens = 81 ether;
        goober.deposit(artGobbler, gooTokens, users[10]);
        vm.stopPrank();

        // Safety check to verify new mint price after warp and mint.
        assertEq(gobblers.gobblerPrice(), 52987405899699731484);

        // Now we have pool virtual goo = 81 and pool mult = 9.
        // The goo/mult of our pool is <= goo/mult of the auction,
        // since: 81 / 9 = 9 >= 52.987 / 7.3294 ~= 7.
        // We also have enough goo to mint a single gobbler.
        // NOTE(Getting both of the above to be true is a very delicate
        // balance, especially tricky if you want to test minting
        // more than 1 gobbler here.)

        // Mint a gobbler, and check we return 1 (gobbler) minted.
        // NOTE(Updates K, reserves and VRGDA in the process.)
        vm.prank(MINTER);
        assertEq(goober.mintGobbler(), 1);
        // Check contract owns second minted gobbler.
        assertEq(gobblers.ownerOf(2), address(goober));

        // Check our Goo balance went down from minting: 81 - 52.99 ~= 28.01.
        (uint112 _GooReserve, uint112 _GobblerReserve,) = goober.getReserves();
        assertEq(_GooReserve, 28012594100300268516);

        // Warp ahead to reveal second gobbler.
        vm.warp(block.timestamp + 1 days);
        // Changing the seed string changes the randomness, and thus the rolled mult.
        _setRandomnessAndReveal(1, "seed2");
        (uint112 _newGooReserve, uint112 _newGobblerReserve,) = goober.getReserves();
        // Check we have 15 total mult including the previous 9, since we minted a 6.
        assertEq(_newGobblerReserve, 15);
        // Check our goo balance updated from emission.
        assertEq(_newGooReserve, 46140671657193055549);

        // NOTE(Checking k uneeded since _update() handles all of that
    }

    // function test_withdraw_minted() public {
    // Test if we can pull a minted Gobbler out of pool)
    //     uint256[] memory artGobblerFromMint = new uint256[](1);
    //     artGobblerFromMint[0] = 2; //Gobbler with tokenId = 2.
    //     vm.prank(users[10]);
    //     goober.withdraw(artGobblerFromMint, 0, users[10], users[10]); //Withdraw Gobbler minted from Goober based on shares minted from kDebt.
    //     assertEq(gobblers.ownerOf(2), users[10]); //Check if we own the Gobbler now.
    // }

    function testMintRevertRatio() public {
        // Safety check to verify starting gobblerPrice is correct.
        assertEq(gobblers.gobblerPrice(), 73013654753028651285);

        /// Add enough Goo to vault to mint a single Gobbler.
        _writeTokenBalance(users[10], address(goo), 1000 ether);

        // Mint the first gobbler
        vm.startPrank(users[10]);
        uint256[] memory artGobbler = new uint256[](1);
        artGobbler[0] = gobblers.mintFromGoo(75 ether, false);
        // Check to see we own the first Gobbler.
        assertEq(gobblers.ownerOf(1), users[10]);
        // Warp a day ahead until we can reveal Gobbler 1.
        vm.warp(block.timestamp + 86400);
        _setRandomnessAndReveal(1, "seed");
        uint256 gobblerMult = (gobblers.getGobblerEmissionMultiple(artGobbler[0]));
        // Based on our seed, we get a mult of 9 here.
        assertEq(gobblerMult, 9);

        // Safety check to verify new mint price after warp and mint.
        assertEq(gobblers.gobblerPrice(), 52987405899699731484);

        // Pool is setup by depositing 2 gobbler and 55 goo.
        // We do this after warp to not accrue extra goo.
        // Depositing automatically makes the goo virtual.
        uint256 gooTokens = 55 ether;
        goober.deposit(artGobbler, gooTokens, users[10]);
        vm.stopPrank();

        // Tries to mint a gobbler and expects revert.
        // We have enough goo to mint, so should revert due
        // to failing to maintain the conditional ratio.
        vm.prank(MINTER);
        vm.expectRevert(bytes("Pool Goo per Mult lower than Auction's"));
        goober.mintGobbler();
    }

    function testRevertMintCaller() public {
        vm.startPrank(msg.sender);
        //Revert if not Minter.
        vm.expectRevert();
        goober.mintGobbler();
        vm.stopPrank();
    }

    function testRevertMintGobblerWhenNotMinter() public {
        vm.expectRevert(abi.encodeWithSelector(IGoober.AccessControlViolation.selector, OTHER, MINTER));
        vm.prank(OTHER);
        goober.mintGobbler();
    }

    function testEmitMintLowGoo() public {
        // TODO(Add custom event emit for too low goo to mint and test it)
    }

    /*//////////////////////////////////////////////////////////////
    // Flag Gobbler
    //////////////////////////////////////////////////////////////*/

    function testFlagGobbler() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(3, "seed");
        vm.stopPrank();

        vm.prank(FEE_TO);
        goober.flagGobbler(artGobblersTwo[0], true);

        vm.startPrank(users[1]);
        goober.deposit(artGobblers, 100 ether, users[1]);

        vm.expectRevert(IGoober.InvalidNFT.selector);

        goober.deposit(artGobblersTwo, 100 ether, users[1]);
    }

    function testUnflagGobbler() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(3, "seed");
        vm.stopPrank();

        vm.startPrank(FEE_TO);
        goober.flagGobbler(artGobblersTwo[0], true);
        goober.flagGobbler(artGobblersTwo[0], false);
        vm.stopPrank();

        // All good
        vm.prank(users[1]);
        goober.deposit(artGobblersTwo, 100 ether, users[1]);
    }

    function testRevertFlagGobblerWhenNotFeeTo() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(3, "seed");
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IGoober.AccessControlViolation.selector, OTHER, FEE_TO));

        vm.prank(OTHER);
        goober.flagGobbler(artGobblersTwo[0], true);
    }

    /*//////////////////////////////////////////////////////////////
    // IERC721Receiver
    //////////////////////////////////////////////////////////////*/

    function testRevertOnERC721ReceivedWhenNotGobblerNFT() public {
        MockERC721 mockNFT = new MockERC721("MockERC721", "MOCK");
        mockNFT.mint(users[1], 1);

        vm.expectRevert(IGoober.InvalidNFT.selector);

        vm.prank(users[1]);
        mockNFT.safeTransferFrom(users[1], address(goober), 1);
    }

    function testRevertOnERC721ReceivedWhenDirectlySendingFlaggedGobbler() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(3, "seed");
        vm.stopPrank();

        vm.prank(FEE_TO);
        goober.flagGobbler(artGobblersTwo[0], true);

        vm.expectRevert(IGoober.InvalidNFT.selector);

        vm.prank(users[1]);
        gobblers.safeTransferFrom(users[1], address(goober), artGobblersTwo[0]);
    }

    function testRevertOnERC721ReceivedWhenDepositingUnrevealedGobbler() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);

        vm.expectRevert(abi.encodeWithSelector(IGoober.InvalidMultiplier.selector, artGobblersTwo[0]));

        goober.deposit(artGobblersTwo, 100 ether, users[1]);
    }

    /*//////////////////////////////////////////////////////////////
    // Protocol Admin
    //////////////////////////////////////////////////////////////*/

    function testSkimGoo() public {
        _writeTokenBalance(address(goober), address(goo), 1 ether);

        // Precondition checks
        assertEq(goo.balanceOf(FEE_TO), 0);
        assertEq(goo.balanceOf(address(goober)), 1 ether);

        vm.prank(FEE_TO);
        goober.skimGoo();

        assertEq(goo.balanceOf(FEE_TO), 1 ether);
        assertEq(goo.balanceOf(address(goober)), 0);
    }

    function testRevertSkimGooWhenNotFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IGoober.AccessControlViolation.selector, OTHER, FEE_TO));

        vm.prank(OTHER);
        goober.skimGoo();
    }

    function testRevertSkimGooWhenNoGooInContract() public {
        vm.expectRevert(IGoober.NoSkim.selector);

        vm.prank(FEE_TO);
        goober.skimGoo();
    }

    function testSetFeeTo() public {
        // Precondition check
        assertEq(goober.feeTo(), FEE_TO);

        vm.prank(FEE_TO);
        goober.setFeeTo(OTHER);

        assertEq(goober.feeTo(), OTHER);
    }

    function testRevertSetFeeToWhenNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(IGoober.AccessControlViolation.selector, OTHER, FEE_TO));

        vm.prank(OTHER);
        goober.setFeeTo(address(0xABCD));
    }

    function testRevertSetFeeToWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IGoober.InvalidAddress.selector, address(0)));

        vm.prank(FEE_TO);
        goober.setFeeTo(address(0));
    }

    function testSetMinter() public {
        // Precondition check
        assertEq(goober.minter(), MINTER);

        vm.prank(FEE_TO); // FEE_TO acts as protocol admin
        goober.setMinter(OTHER);

        assertEq(goober.minter(), OTHER);
    }

    function testRevertSetMinterWhenNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(IGoober.AccessControlViolation.selector, OTHER, FEE_TO));

        vm.prank(OTHER);
        goober.setMinter(address(0xABCD));
    }

    function testRevertSetMinterWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IGoober.InvalidAddress.selector, address(0)));

        vm.prank(FEE_TO);
        goober.setMinter(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        Test Helpers
    //////////////////////////////////////////////////////////////*/

    function _writeTokenBalance(address who, address token, uint256 amt) internal {
        stdstore.target(token).sig(IERC20(token).balanceOf.selector).with_key(who).checked_write(amt);
    }

    function _addGooAndMintGobblers(uint256 _gooAmount, uint256 _numGobblers) internal returns (uint256[] memory) {
        // TODO add input validation check
        gobblers.addGoo(_gooAmount);
        uint256[] memory artGobblers = new uint256[](_numGobblers);
        for (uint256 i = 0; i < _numGobblers; i++) {
            artGobblers[i] = gobblers.mintFromGoo(100 ether, true);
        }
        return artGobblers;
    }

    /// @dev Call back vrf with randomness and reveal gobblers.
    function _setRandomnessAndReveal(uint256 numReveal, string memory seed) internal {
        bytes32 requestId = gobblers.requestRandomSeed();
        uint256 randomness = uint256(keccak256(abi.encodePacked(seed)));
        // call back from coordinator
        vrfCoordinator.callBackWithRandomness(requestId, randomness, address(randProvider));
        gobblers.revealGobblers(numReveal);
    }

    /*//////////////////////////////////////////////////////////////
                        Events
    //////////////////////////////////////////////////////////////*/

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

    event Sync(uint112 gooBalance, uint112 multBalance);
}
