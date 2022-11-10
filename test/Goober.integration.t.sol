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

    // TODO
    // function testDepositIntegration(
    //     uint256 gooAmount1,
    //     uint256 gobblerAmount1,
    //     uint256 gooAmount2,
    //     uint256 gobblerAmount2,
    //     uint256 gooAmount3,
    //     uint256 gobblerAmount3,
    //     uint256 gooAmount4,
    //     uint256 gobblerAmount4,
    //     uint256 gooAmount5,
    //     uint256 gobblerAmount5,
    //     uint256 timeSeed
    // ) public {
    //     gooAmount1 = bound(gooAmount1, 100 ether, 1000 ether);
    //     gobblerAmount1 = bound(gobblerAmount1, 1, 3);
    //     gooAmount2 = bound(gooAmount2, 100 ether, 1000 ether);
    //     gobblerAmount2 = bound(gobblerAmount2, 1, 3);
    //     gooAmount3 = bound(gooAmount3, 100 ether, 1000 ether);
    //     gobblerAmount3 = bound(gobblerAmount3, 1, 3);
    //     gooAmount4 = bound(gooAmount4, 100 ether, 1000 ether);
    //     gobblerAmount4 = bound(gobblerAmount4, 1, 3);
    //     gooAmount5 = bound(gooAmount5, 100 ether, 1000 ether);
    //     gobblerAmount5 = bound(gobblerAmount5, 1, 3);

    //     // Broken -- getting an overflow from ArtGobblers.mintFromGoo()

    //     vm.prank(users[1]);
    //     _addGooAndMintGobblers(gooAmount1, gobblerAmount1);
    //     vm.prank(users[2]);
    //     _addGooAndMintGobblers(gooAmount2, gobblerAmount2);
    //     vm.prank(users[3]);
    //     _addGooAndMintGobblers(gooAmount3, gobblerAmount3);
    //     vm.prank(users[4]);
    //     _addGooAndMintGobblers(gooAmount4, gobblerAmount4);
    //     vm.prank(users[5]);
    //     _addGooAndMintGobblers(gooAmount5, gobblerAmount5);

    //     vm.warp(TIME0 + 1 days);
    //     _setRandomnessAndReveal(
    //         gobblerAmount1 + gobblerAmount2 + gobblerAmount3 + gobblerAmount4 + gobblerAmount5, "seed"
    //     );

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
