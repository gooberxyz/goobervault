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
import "../src/GooberPeriphery.sol";

contract GooberPeripheryTest is Test {
    using stdStorage for StdStorage;

    Goober internal goober;
    GooberPeriphery internal periphery;

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

        periphery = new GooberPeriphery(address(goober));

        // Setup balances and approvals
        for (uint256 i = 1; i < 11; i++) {
            _writeTokenBalance(users[i], address(goo), START_BAL);

            vm.startPrank(users[i]);
            goo.approve(address(periphery), type(uint256).max);
            gobblers.setApprovalForAll(address(periphery), true);
            goober.approve(address(periphery), type(uint256).max);
            vm.stopPrank();
        }
    }

    /*//////////////////////////////////////////////////////////////
    // Deposit
    //////////////////////////////////////////////////////////////*/

    function testDeposit() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblers, gooToDeposit);

        uint256 fractions =
            periphery.deposit(artGobblers, gooToDeposit, users[1], expectedFractions, block.timestamp + 1);
        vm.stopPrank();

        // Fractions are minted to depositor
        assertEq(goober.balanceOf(users[1]), fractions);
    }

    function testDepositFailsWhenExpired() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblers, gooToDeposit);

        vm.expectRevert("GooberPeriphery: EXPIRED");

        periphery.deposit(artGobblers, gooToDeposit, users[1], expectedFractions, block.timestamp - 1);
    }

    function testDepositFailsWhenInsufficientLiquidityMinted() public {
        // Add Goo and mint Gobblers
        vm.startPrank(users[1]);
        uint256[] memory artGobblers = _addGooAndMintGobblers(500 ether, 2);

        uint256 gooToDeposit = 200 ether;

        // Reveal
        vm.warp(TIME0 + 1 days);
        _setRandomnessAndReveal(2, "seed");

        // Deposit 2 gobblers and 200 goo
        uint256 expectedFractions = goober.previewDeposit(artGobblers, gooToDeposit);

        vm.expectRevert("GooberPeriphery: INSUFFICIENT_LIQUIDITY_MINTED");

        periphery.deposit(artGobblers, gooToDeposit, users[1], expectedFractions + 1, block.timestamp + 1);
    }

    /*//////////////////////////////////////////////////////////////
    // Withdraw
    //////////////////////////////////////////////////////////////*/

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

        periphery.deposit(artGobblers, gooToDeposit, users[1], expectedFractionsOut, block.timestamp + 1);

        vm.warp(block.timestamp + 7 days);

        uint256 userGooBefore = goo.balanceOf(users[1]);
        uint256 gooToWithdraw = 10 ether;

        uint256 expectedFractionsIn = goober.previewWithdraw(artGobblersToWithdraw, gooToWithdraw);

        uint256 fractionsIn = periphery.withdraw(
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

    function testWithdrawFailsWhenExpired() public {
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

        periphery.deposit(artGobblers, gooToDeposit, users[1], expectedFractionsOut, block.timestamp + 1);

        vm.warp(block.timestamp + 7 days);

        uint256 gooToWithdraw = 10 ether;

        uint256 expectedFractionsIn = goober.previewWithdraw(artGobblersToWithdraw, gooToWithdraw);

        vm.expectRevert("GooberPeriphery: EXPIRED");

        periphery.withdraw(
            artGobblersToWithdraw, gooToWithdraw, users[1], users[1], expectedFractionsIn, block.timestamp - 1
        );
    }

    function testWithdrawFailsWhenFractionsBurnedExceedsLimit() public {
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

        periphery.deposit(artGobblers, gooToDeposit, users[1], expectedFractionsOut, block.timestamp + 1);

        vm.warp(block.timestamp + 7 days);

        uint256 gooToWithdraw = 10 ether;

        uint256 expectedFractionsIn = goober.previewWithdraw(artGobblersToWithdraw, gooToWithdraw);

        vm.expectRevert("GooberPeriphery: BURN_ABOVE_LIMIT");

        periphery.withdraw(
            artGobblersToWithdraw, gooToWithdraw, users[1], users[1], expectedFractionsIn - 1, block.timestamp + 1
        );
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
}
