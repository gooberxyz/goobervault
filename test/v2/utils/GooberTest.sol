// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../mocks/MockERC721.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import "art-gobblers/Goo.sol";
import "art-gobblers/../test/utils/mocks/LinkToken.sol";
import "art-gobblers/../lib/chainlink/contracts/src/v0.8/mocks/VRFCoordinatorMock.sol";
import {ChainlinkV1RandProvider} from "art-gobblers/utils/rand/ChainlinkV1RandProvider.sol";
import {Utilities} from "art-gobblers/../test/utils/Utilities.sol";
import "art-gobblers/utils/GobblerReserve.sol";

import "../../../src/v2/Goober.sol";
import "../../../src/v2/interfaces/IGoober.sol";

abstract contract GooberTest is Test {
    //
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

    struct SwapParams {
        uint256[] gobblersOut;
        uint256 gooOut;
        uint256[] gobblersIn;
        uint256 gooIn;
        address receiver;
        bytes data;
    }

    function setUp() public virtual {
        vm.warp(TIME0);

        utils = new Utilities();
        users = utils.createUsers(11);
        linkToken = new LinkToken();
        vrfCoordinator = new VRFCoordinatorMock(address(linkToken));

        // Deploy Art Gobblers contracts
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
    }

    /*//////////////////////////////////////////////////////////////
                        Test Helpers
    //////////////////////////////////////////////////////////////*/

    /// @dev TODO
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

    /// @dev TODO
    function _addGooAndMintGobblers(uint256 _gooAmount, uint256 _numGobblers) internal returns (uint256[] memory) {
        // TODO add input validation check
        gobblers.addGoo(_gooAmount);
        uint256[] memory artGobblers = new uint256[](_numGobblers);
        for (uint256 i = 0; i < _numGobblers; i++) {
            artGobblers[i] = gobblers.mintFromGoo(100 ether, true);
        }
        return artGobblers;
    }
}
