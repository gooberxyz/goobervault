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

    uint256[] internal gobblerPool;

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

        // Approve all goo to Goober
        goo.approve(address(goober), type(uint256).max);

        // Approve all gobbler to Goober
        gobblers.setApprovalForAll(address(goober), true);

        // Mint a pool of 300 Gobblers. Actors can draw from
        // this pool when they need Gobblers to swap/deposit.
        gobblerPool = _mintGobblers(address(this), 300);

        // Warp forward a full year, since the VRGDA price
        // of Gobblers is now very high.
        vm.warp(block.timestamp + 365 days);
    }

    function _drawGobblers(uint256 numGobblers) internal returns (uint256[] memory) {
        uint256[] memory gobblerIds = new uint256[](numGobblers);
        for (uint256 i; i < numGobblers; i++) {
            gobblerIds[i] = gobblerPool[gobblerPool.length - 1];
            gobblerPool.pop();
        }
        return gobblerIds;
    }

    function _returnGobblers(uint256[] memory gobblerIds) internal {
        for (uint256 i; i < gobblerIds.length; i++) {
            gobblerPool.push(gobblerIds[i]);
        }
    }

    function _mintGobblers(address who, uint256 numGobblers) private returns (uint256[] memory) {
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
    function _setRandomnessAndReveal(uint256 numReveal, string memory seed) private {
        bytes32 requestId = gobblers.requestRandomSeed();
        uint256 randomness = uint256(keccak256(abi.encodePacked(seed)));
        // call back from coordinator
        vrfCoordinator.callBackWithRandomness(requestId, randomness, address(randProvider));
        gobblers.revealGobblers(numReveal);
    }
}

/// @dev The InvariantWarper warps forward a random number of days.
contract InvariantWarper is CommonBase {
    function warp(uint8 numDays) external {
        vm.warp(block.timestamp + uint256(numDays) * 1 days);
    }
}

/// @dev The InvariantAdmin randomly mints Gobblers and skims.
contract InvariantAdmin is InvariantActor {
    address internal constant FEE_TO = address(0xFEEE);
    address internal constant MINTER = address(0x1337);

    constructor(
        Goober _goober,
        Goo _goo,
        ArtGobblers _gobblers,
        RandProvider _randProvider,
        VRFCoordinatorMock _vrfCoordinator
    ) InvariantActor(_goober, _goo, _gobblers, _randProvider, _vrfCoordinator) {}

    function mint() external {
        vm.prank(MINTER);
        goober.mintGobbler();
    }

    function skim() external {
        vm.prank(FEE_TO);
        goober.skimGoo();
    }
}

/// @dev The InvariantUser calls deposit, withdraw, and swap.
contract InvariantUser is InvariantActor {
    uint256 depositedGoo;
    uint256[] depositedGobblers;

    uint256 public depositCalls;
    uint256 public withdrawCalls;
    uint256 public swapGobblersForGobblersCalls;
    uint256 public swapGooForGobblersCalls;
    uint256 public swapGobblersForGooCalls;

    constructor(
        Goober _goober,
        Goo _goo,
        ArtGobblers _gobblers,
        RandProvider _randProvider,
        VRFCoordinatorMock _vrfCoordinator
    ) InvariantActor(_goober, _goo, _gobblers, _randProvider, _vrfCoordinator) {}

    function deposit(uint8 _gooTokens, uint8 _numGobblers) external {
        // convert _gooTokens to an amount between 10 and 2550 Goo.
        uint256 gooTokens = uint256(_gooTokens) * 10 ether;

        // convert _numGobblers to an amount between 0-10.
        uint256 numGobblers = _numGobblers % 11;

        // Draw gobblers from the pool
        uint256[] memory gobblersIn = _drawGobblers(numGobblers);

        // Mint ourselves Goo equal to the deposit amount
        _writeTokenBalance(address(this), address(goo), gooTokens);

        // Account for deposited goo and gobblers.
        for (uint256 i; i < gobblersIn.length; i++) {
            depositedGobblers.push(gobblersIn[i]);
        }
        depositedGoo += gooTokens;

        // Perform deposit
        goober.deposit(gobblersIn, gooTokens, address(this));
    }

    function withdraw(uint8 _gooNum, uint8 _gobblerNum) external {
        // Use _gooNum to calculate the proportion of deposited goo to withdraw.
        uint256 gooTokens = depositedGoo * uint256(_gooNum) / type(uint8).max;

        // Use _gobblerNum to calculate the proportion of deposited gobblers to withdraw.
        uint256 numGobblers = depositedGobblers.length * uint256(_gobblerNum) / type(uint8).max;

        // Remove gobblers from the depositedGobblers array.
        uint256[] memory gobblersOut = new uint256[](numGobblers);
        for (uint256 i; i < numGobblers; i++) {
            gobblersOut[i] = depositedGobblers[depositedGobblers.length - 1];
            depositedGobblers.pop();
        }
        // Account for withdrawn goo.
        depositedGoo -= gooTokens;

        // Return removed gobblers to the pool.
        _returnGobblers(gobblersOut);

        // Perform withdrawal
        goober.withdraw(gobblersOut, gooTokens, address(this), address(this));
    }

    function swapGobblersForGobblers(uint8 _swapGobblers, uint8 _poolGobblers) external {
        // Convert _swapGobblers to a number between 1-10.
        // Draw this many gobblers from the pool.
        uint256 swapGobblers = _swapGobblers % 10 + 1;
        uint256[] memory gobblersIn = _drawGobblers(swapGobblers);

        // Convert _poolGobblers to a number between 1-10
        uint256 poolGobblers = _poolGobblers % 10 + 1;

        // We can't swap for more gobblers than are in the Goober pool
        poolGobblers = poolGobblers > depositedGobblers.length ? depositedGobblers.length : poolGobblers;

        // Get the ids of gobblers we know are deposited
        uint256[] memory gobblersOut = new uint256[](poolGobblers);
        for (uint256 i; i < poolGobblers; i++) {
            gobblersOut[i] = depositedGobblers[depositedGobblers.length - 1];
            depositedGobblers.pop();
        }

        // Add the gobblers we're swapping to the depositedGobblers array
        for (uint256 i; i < swapGobblers; i++) {
            depositedGobblers.push(gobblersIn[i]);
        }

        // Preview the swap to determine how much Goo we need to provide.
        int256 erroneousGoo =
            goober.previewSwap({gobblersOut: gobblersOut, gooOut: 0, gobblersIn: gobblersIn, gooIn: 0});

        // If we need to provide more goo, mint it
        if (erroneousGoo > 0) {
            _writeTokenBalance(address(this), address(goo), uint256(erroneousGoo));
        }
        uint256 gooIn = (erroneousGoo > 0) ? uint256(erroneousGoo) : 0;

        // Perform the swap
        goober.swap({
            gobblersOut: gobblersOut,
            gooOut: 0,
            gobblersIn: gobblersIn,
            gooIn: gooIn,
            receiver: address(this),
            data: bytes("")
        });
    }

    function swapGobblersForGoo(uint8 _swapGobblers) external {
        // Convert _swapGobblers to a number between 1-10.
        // Draw this many gobblers from the pool.
        uint256 swapGobblers = _swapGobblers % 10 + 1;
        uint256[] memory gobblersIn = _drawGobblers(swapGobblers);

        // Push these gobblers in to the depositedGobblers array
        for (uint256 i; i < swapGobblers; i++) {
            depositedGobblers.push(gobblersIn[i]);
        }

        // No gobblersOut, since we are swapping for Goo only
        uint256[] memory gobblersOut = new uint256[](0);

        // Preview the swap to determine how much Goo we expect
        int256 erroneousGoo =
            goober.previewSwap({gobblersOut: gobblersOut, gooOut: 1, gobblersIn: gobblersIn, gooIn: 0});

        // erroneousGoo will be negative, convert to a positive amount
        uint256 gooOut = (erroneousGoo < 0) ? uint256(-1 * erroneousGoo) : 0;

        // Perform the swap
        goober.swap({
            gobblersOut: gobblersOut,
            gooOut: gooOut,
            gobblersIn: gobblersIn,
            gooIn: 0,
            receiver: address(this),
            data: bytes("")
        });
    }

    function swapGooForGobblers(uint8 _poolGobblers) external {
        // No gobblersIn for this swap.
        uint256[] memory gobblersIn = new uint256[](0);

        // Convert _poolGobblers to a number between 1-10
        uint256 poolGobblers = _poolGobblers % 10 + 1;

        // We can't swap for more gobblers than are in the Goober pool
        poolGobblers = poolGobblers > depositedGobblers.length ? depositedGobblers.length : poolGobblers;

        // Get the ids of gobblers we know are deposited
        uint256[] memory gobblersOut = new uint256[](poolGobblers);
        for (uint256 i; i < poolGobblers; i++) {
            gobblersOut[i] = depositedGobblers[depositedGobblers.length - 1];
            depositedGobblers.pop();
        }

        // Preview the swap to work out how much Goo we need to provide
        int256 erroneousGoo =
            goober.previewSwap({gobblersOut: gobblersOut, gooOut: 0, gobblersIn: gobblersIn, gooIn: 1});

        // Calculate gooIn based on the preview, and mint Goo to swap.
        if (erroneousGoo > 0) {
            _writeTokenBalance(address(this), address(goo), uint256(erroneousGoo));
        }
        uint256 gooIn = (erroneousGoo > 0) ? uint256(erroneousGoo) : 0;

        // Perform the swap
        goober.swap({
            gobblersOut: gobblersOut,
            gooOut: 0,
            gobblersIn: gobblersIn,
            gooIn: gooIn,
            receiver: address(this),
            data: bytes("")
        });
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

    InvariantUser internal user;
    InvariantAdmin internal admin;
    InvariantWarper internal warper;

    bytes32 private keyHash;
    uint256 private fee;

    uint256[] internal ids;

    uint256 internal constant START_BAL = 2000 ether;
    uint256 internal constant TIME0 = 2_000_000_000; // now-ish unix timestamp

    address[] private _targetContracts;

    uint256 prevGooBalance;
    uint256 prevGbrFeeBalance;

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

        user = new InvariantUser({
            _goo: goo,
            _gobblers: gobblers,
            _goober: goober,
            _vrfCoordinator: vrfCoordinator,
            _randProvider: randProvider
        });

        admin = new InvariantAdmin({
            _goo: goo,
            _gobblers: gobblers,
            _goober: goober,
            _vrfCoordinator: vrfCoordinator,
            _randProvider: randProvider
        });

        warper = new InvariantWarper();

        _addTargetContract(address(user));
        _addTargetContract(address(admin));
        _addTargetContract(address(warper));
    }

    function invariant_goo_balance() public {
        // I am surprised this passes: isn't it possible for goo
        // balances to decrease with withdrawals?
        uint256 gooBalance = gobblers.gooBalance(address(goober));
        assertGe(gooBalance, prevGooBalance);
        prevGooBalance = gooBalance;
    }

    function invariant_fee_balance() public {
        uint256 gbrFeeBalance = goober.balanceOf(FEE_TO);
        assertGe(gbrFeeBalance, prevGbrFeeBalance);
        prevGbrFeeBalance = gbrFeeBalance;
    }

    /*//////////////////////////////////////////////////////////////
                        Test Helpers
    //////////////////////////////////////////////////////////////*/

    function _writeTokenBalance(address who, address token, uint256 amt) internal {
        stdstore.target(token).sig(IERC20(token).balanceOf.selector).with_key(who).checked_write(amt);
    }
}
