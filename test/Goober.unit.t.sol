// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import "art-gobblers/Goo.sol";
import "art-gobblers/../test/utils/mocks/LinkToken.sol";
import "art-gobblers/../lib/chainlink/contracts/src/v0.8/mocks/VRFCoordinatorMock.sol";
import {ChainlinkV1RandProvider} from "art-gobblers/utils/rand/ChainlinkV1RandProvider.sol";
import {Utilities} from "art-gobblers/../test/utils/Utilities.sol";
import "art-gobblers/utils/GobblerReserve.sol";

import "../src/Goober.sol";
import "../src/interfaces/IGoober.sol";

contract GooberTest is Test {
    using stdStorage for StdStorage;

    Goober internal goober;

    Utilities internal utils;
    address payable[] internal users;
    address internal FEE_TO = address(0xFEEE);
    address internal MINTER = address(0x1337);
    address internal OTHER = address(0xDEAD);

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

    uint256 internal START_BAL = 2000 * 10 ** 18;

    function setUp() public {
        //
        utils = new Utilities();
        users = utils.createUsers(6);
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
            _feeTo: FEE_TO,
            _minter: MINTER
        });

        // Setup balances
        _writeTokenBalance(users[1], address(goo), START_BAL);
        _writeTokenBalance(users[2], address(goo), START_BAL);
        _writeTokenBalance(users[3], address(goo), START_BAL);
        _writeTokenBalance(users[4], address(goo), START_BAL);
        _writeTokenBalance(users[5], address(goo), START_BAL);

        // Setup approvals
        vm.startPrank(users[1]);
        goo.approve(address(goober), type(uint256).max);
        gobblers.setApprovalForAll(address(goober), true);
        vm.stopPrank();
        vm.startPrank(users[2]);
        goo.approve(address(goober), type(uint256).max);
        gobblers.setApprovalForAll(address(goober), true);
        vm.stopPrank();
        vm.startPrank(users[3]);
        goo.approve(address(goober), type(uint256).max);
        gobblers.setApprovalForAll(address(goober), true);
        vm.stopPrank();
        vm.startPrank(users[4]);
        goo.approve(address(goober), type(uint256).max);
        gobblers.setApprovalForAll(address(goober), true);
        vm.stopPrank();
        vm.startPrank(users[5]);
        goo.approve(address(goober), type(uint256).max);
        gobblers.setApprovalForAll(address(goober), true);
        vm.stopPrank();
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

    /*//////////////////////////////////////////////////////////////
                        Deposit
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
        gobblers.addGoo(500 * 10 ** 18);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersHold = new uint256[](1);

        artGobblers[0] = gobblers.mintFromGoo(100 * 10 ** 18, true);
        artGobblers[1] = gobblers.mintFromGoo(100 * 10 ** 18, true);
        artGobblersHold[0] = gobblers.mintFromGoo(100 * 10 ** 18, true);

        // Precondition checks
        uint256 gooToDeposit = 200 * 10 ** 18;
        // assertEq(gobblers.gooBalance(users[1]), x); TODO
        assertEq(gobblers.gooBalance(address(goober)), 0);
        assertEq(gobblers.ownerOf(artGobblers[0]), users[1]);
        assertEq(gobblers.ownerOf(artGobblers[1]), users[1]);

        vm.warp(block.timestamp + 172_800);

        _setRandomnessAndReveal(3, "seed");

        vm.expectEmit(true, true, true, false);
        emit Deposit(users[1], users[1], artGobblers, gooToDeposit, 999);

        /*uint256 fractions = */
        goober.deposit(artGobblers, gooToDeposit, users[1]);

        // Goo is transferred into vault
        // assertEq(gobblers.gooBalance(users[1]), x); TODO
        assertEq(gobblers.gooBalance(address(goober)), gooToDeposit);

        // Gobblers are transferred into vault
        assertEq(gobblers.ownerOf(artGobblers[0]), address(goober));
        assertEq(gobblers.ownerOf(artGobblers[1]), address(goober));

        // Fractions are minted to depositor
        // TODO

        // Reserve balances and total assets are updated
        // TODO

        // Management and performance fees were accrued
        // TODO
    }

    // function testDepositWhenOnlyGoo() public {

    // }

    // function testDepositWhenOnlyGobblers() public {

    // }

    // function testEventDeposit() public {

    // }

    // function testRevertDepositWhenInsufficientLiquidityMined() public {
    //     // Goober: INSUFFICIENT_LIQUIDITY_MINTED
    // }

    /*//////////////////////////////////////////////////////////////
                        Withdraw
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
        gobblers.addGoo(500 * 10 ** 18);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersHold = new uint256[](1);
        uint256[] memory artGobblersToWithdraw = new uint256[](1);

        artGobblers[0] = gobblers.mintFromGoo(100 * 10 ** 18, true);
        artGobblers[1] = gobblers.mintFromGoo(100 * 10 ** 18, true);
        artGobblersHold[0] = gobblers.mintFromGoo(100 * 10 ** 18, true);
        artGobblersToWithdraw[0] = artGobblers[0];

        vm.warp(block.timestamp + 172_800);

        _setRandomnessAndReveal(3, "seed");

        /*uint256 fractions = */
        goober.deposit(artGobblers, 500 * 10 ** 18, users[1]);

        // TODO

        vm.warp(block.timestamp + 7 days);

        goober.withdraw(artGobblersToWithdraw, 10 * 10 ** 18, users[1], users[1]);

        // TODO
    }

    // function testWithdrawWhenDepositedOnlyGoo() public {}

    // function testWithdrawWhenDepositedOnlyGobblers() public {}

    // test withdraw when owner != receiver

    // testEventWithdraw

    // Goober: INSUFFICIENT LIQUIDITY WITHDRAW edge cases

    function testRevertWithdrawWhenInsufficientGobblerMult() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 * 10 ** 18);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersHold = new uint256[](1);

        artGobblers[0] = gobblers.mintFromGoo(100 * 10 ** 18, true);
        artGobblers[1] = gobblers.mintFromGoo(100 * 10 ** 18, true);
        artGobblersHold[0] = gobblers.mintFromGoo(100 * 10 ** 18, true);

        vm.warp(block.timestamp + 172_800);

        _setRandomnessAndReveal(3, "seed");

        goober.deposit(artGobblers, 500 * 10 ** 18, users[1]);

        vm.expectRevert("Goober: MUST LEAVE LIQUIDITY");

        goober.withdraw(new uint256[](0), 500 * 10 ** 18, users[1], users[1]);
    }

    // function testRevertWithdrawWhenWithdrawingLastGoo() public {

    // }

    function testRevertWithdrawWhenWithdrawingLastGobbler() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 * 10 ** 18);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersHold = new uint256[](1);

        artGobblers[0] = gobblers.mintFromGoo(100 * 10 ** 18, true);
        artGobblers[1] = gobblers.mintFromGoo(100 * 10 ** 18, true);
        artGobblersHold[0] = gobblers.mintFromGoo(100 * 10 ** 18, true);

        vm.warp(block.timestamp + 172_800);

        _setRandomnessAndReveal(3, "seed");

        goober.deposit(artGobblers, 500 * 10 ** 18, users[1]);

        vm.expectRevert("Goober: MUST LEAVE LIQUIDITY");

        goober.withdraw(artGobblers, 10 * 10 ** 18, users[1], users[1]);
    }

    // Goober: INSUFFICIENT_ALLOWANCE

    /*//////////////////////////////////////////////////////////////
                        Swap
    //////////////////////////////////////////////////////////////*/

    // Check at least some Goo or Gobblers are being swapped out
    // Get reserves
    // Check receiver address is not Goo nor Gobbler
    // Transfer any Goo or Gobblers to correct out addresses
    // If flash loan —
    //      Transfer any Goo or Gobblers IN
    // Get reserves again
    // Calculate amounts in
    // Check at least some Goo or Gobblers are being swapped in
    // Check k
    // Assess performance fee on growth of k
    // Update reserves
    // Emit event

    function testSwap() public {
        vm.startPrank(users[1]);
        gobblers.addGoo(500 * 10 ** 18);

        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        uint256[] memory artGobblersThree = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 * 10 ** 18, true);
        artGobblers[1] = gobblers.mintFromGoo(100 * 10 ** 18, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 * 10 ** 18, true);
        artGobblersThree[0] = artGobblers[0];

        vm.warp(block.timestamp + 172800);

        _setRandomnessAndReveal(3, "seed");

        uint256 gooTokens = 200 * 10 ** 18;
        uint256 fractions = goober.deposit(artGobblers, gooTokens, users[1]);

        // TODO

        bytes memory data;
        IGoober.SwapParams memory swap =
            IGoober.SwapParams(artGobblersThree, 0 * 10 ** 18, artGobblersTwo, 100 * 10 ** 18, users[1], data);
        goober.swap(swap);

        fractions = goober.withdraw(artGobblersTwo, 100 * 10 ** 18, users[1], users[1]);

        // TODO assertions
    }

    // Goober: INSUFFICIENT_OUTPUT_AMOUNT

    // Goober: INVALID_TO

    // Goober: INSUFFICIENT_INPUT_AMOUNT

    /*//////////////////////////////////////////////////////////////
                        Accounting
    //////////////////////////////////////////////////////////////*/

    // totalAssets
    // getReserves
    // convertToFractions
    // convertToAssets
    // previewDeposit / previewFractionsToMintOnDeposit
    // previewWithdraw / previewFractionsToBurnOnWithdraw
    // previewSwap

    /*//////////////////////////////////////////////////////////////
                        Mint Gobbler
    //////////////////////////////////////////////////////////////*/

    //
    function testRevertMintGobblerWhenNotMinter() public {
        vm.expectRevert(abi.encodeWithSelector(IGoober.AccessControlViolation.selector, OTHER, MINTER));

        vm.prank(OTHER);
        goober.mintGobbler();
    }

    /*//////////////////////////////////////////////////////////////
                        Protocol Admin
    //////////////////////////////////////////////////////////////*/

    // function testSkimGoo() public {
    //     _writeTokenBalance(address(goober), address(goo), 1);
    //     assertEq(goo.balanceOf(address(this)), 0);
    //     assertEq(goo.balanceOf(address(goober)), 1);

    //     // Revert if not owner
    //     vm.startPrank(msg.sender);
    //     // vm.expectRevert(abi.encodeWithSelector(goober.AccessControlViolation.selector, msg.sender, address(this) ) );
    //     vm.expectRevert();
    //     goober.skimGoo();
    //     assertEq(goo.balanceOf(address(this)), 0);
    //     assertEq(goo.balanceOf(address(goober)), 1);
    //     vm.stopPrank();

    //     // Pass
    //     goober.skimGoo();
    //     assertEq(goo.balanceOf(address(this)), 1);
    //     assertEq(goo.balanceOf(address(goober)), 0);

    //     // Revert when no goo in goobler contract
    //     vm.expectRevert("NO_GOO_IN_CONTRACT");
    //     goober.skimGoo();
    // }

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

    // TODO(Duplicating these is sub optimal, we should use the interface)

    event Deposit(
        address indexed caller, address indexed receiver, uint256[] gobblers, uint256 gooTokens, uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256[] gobblers,
        uint256 gooTokens,
        uint256 shares
    );

    event FeesAccrued(address indexed feeTo, uint256 shares, bool performanceFee);

    event Swap(
        address indexed sender,
        address indexed receiver,
        uint256 gooTokensIn,
        uint256 gobblersMultIn,
        uint256 gooTokensOut,
        uint256 gobblerMultOut
    );

    event Sync(uint112 gooBalance, uint112 multBalance);
}
