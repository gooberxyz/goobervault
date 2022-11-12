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

abstract contract InvariantActor is StdUtils, CommonBase {
    using stdStorage for StdStorage;

    Goober internal goober;
    Goo internal goo;
    ArtGobblers internal gobblers;
    RandProvider internal randProvider;
    VRFCoordinatorMock internal vrfCoordinator;

    constructor(
        Goober _goober,
        Goo _goo,
        ArtGobblers _gobblers,
        RandProvider _randProvider,
        VRFCoordinatorMock _vrfCoordinator
    ) {
        goober = _goober;
        goo = _goo;
        gobblers = _gobblers;
        randProvider = _randProvider;
        vrfCoordinator = _vrfCoordinator;

        goo.approve(address(goober), type(uint256).max);
        gobblers.setApprovalForAll(address(goober), true);
    }

    event GobblerPrice(uint256 price);

    function _mintGobblers(address who, uint256 numGobblers) internal returns (uint256[] memory) {
        uint256[] memory mintedGobblers = new uint256[](numGobblers);
        if (numGobblers == 0) return mintedGobblers;
        for (uint256 i = 0; i < numGobblers; i++) {
            uint256 price = gobblers.gobblerPrice();
            _writeTokenBalance(address(this), address(goo), price);
            gobblers.addGoo(price);
            uint256 id = gobblers.mintFromGoo(price, true);
            gobblers.transferFrom(address(this), who, id);
            mintedGobblers[i] = id;
        }
        vm.warp(block.timestamp + 1 days);
        _setRandomnessAndReveal(numGobblers, "seed");
        return mintedGobblers;
    }

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

contract InvariantSwapper is InvariantActor {
    constructor(
        Goober _goober,
        Goo _goo,
        ArtGobblers _gobblers,
        RandProvider _randProvider,
        VRFCoordinatorMock _vrfCoordinator
    ) InvariantActor(_goober, _goo, _gobblers, _randProvider, _vrfCoordinator) {}

    function swap(uint8 gooIn, uint8 swapGobblers, uint8 poolGobblers, uint8 gooOut) external {
        uint256[] memory gobblersIn = _mintGobblers(address(this), swapGobblers);
        uint256[] memory gobblersOut = _mintGobblers(address(goober), poolGobblers);

        _writeTokenBalance(address(this), address(goo), gooIn);

        goober.swap(gobblersOut, gooOut, gobblersIn, gooIn, address(this), bytes(""));
    }
}

contract InvariantLP is InvariantActor {
    constructor(
        Goober _goober,
        Goo _goo,
        ArtGobblers _gobblers,
        RandProvider _randProvider,
        VRFCoordinatorMock _vrfCoordinator
    ) InvariantActor(_goober, _goo, _gobblers, _randProvider, _vrfCoordinator) {}

    function deposit(uint8 _gooTokens, uint8 _numGobblers) external {
        // Convert to wad — range will be 0-255 GOO
        uint256 gooTokens = uint256(_gooTokens) * 10 ether;

        // Limit Gobbler mints to 7. This prevents the VRGDA price from increasing
        // so high it overflows later calculations.
        uint256 numGobblers = _numGobblers % 8;

        uint256[] memory gobblersIn = _mintGobblers(address(this), numGobblers);
        _writeTokenBalance(address(this), address(goo), gooTokens);

        goober.deposit(gobblersIn, gooTokens, address(this));
    }
}

contract GooberInvariantsTest is Test {
    using stdStorage for StdStorage;

    Goober internal goober;

    Utilities internal utils;
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

    InvariantSwapper internal swapper;
    InvariantLP internal lp;

    bytes32 private keyHash;
    uint256 private fee;

    uint256[] internal ids;

    uint256 internal constant START_BAL = 2000 ether;
    uint256 internal constant TIME0 = 2_000_000_000; // now-ish unix timestamp

    address[] private _targetContracts;

    function _addTargetContract(address newTargetContract_) internal {
        _targetContracts.push(newTargetContract_);
    }

    function targetContracts() public view returns (address[] memory targetContracts_) {
        require(_targetContracts.length != uint256(0), "NO_TARGET_CONTRACTS");
        return _targetContracts;
    }

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
            _merkleRoot: keccak256(""),
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

        swapper = new InvariantSwapper({
            _goo: goo,
            _gobblers: gobblers,
            _goober: goober,
            _vrfCoordinator: vrfCoordinator,
            _randProvider: randProvider
        });

        lp = new InvariantLP({
            _goo: goo,
            _gobblers: gobblers,
            _goober: goober,
            _vrfCoordinator: vrfCoordinator,
            _randProvider: randProvider
        });

        _addTargetContract(address(lp));
        //_addTargetContract(address(swapper));
    }

    function invariant_balances() public {
        assertEq(gobblers.gooBalance(address(goober)), 0);
    }

    function test_concrete() public {
        lp.deposit(254, 255);
    }

    /*//////////////////////////////////////////////////////////////
                        Test Helpers
    //////////////////////////////////////////////////////////////*/

    function _writeTokenBalance(address who, address token, uint256 amt) internal {
        stdstore.target(token).sig(IERC20(token).balanceOf.selector).with_key(who).checked_write(amt);
    }
}
