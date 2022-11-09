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

contract TestUERC20Functionality is Test, IERC721Receiver {
    using stdStorage for StdStorage;

    // Test Contracts
    Goober public goober;

    Utilities internal utils;
    address payable[] internal users;

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

    uint256[] ids;

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _writeTokenBalance(address who, address token, uint256 amt) internal {
        stdstore.target(token).sig(IERC20(token).balanceOf.selector).with_key(who).checked_write(amt);
    }

    /// @notice Call back vrf with randomness and reveal gobblers.
    function setRandomnessAndReveal(uint256 numReveal, string memory seed) internal {
        bytes32 requestId = gobblers.requestRandomSeed();
        uint256 randomness = uint256(keccak256(abi.encodePacked(seed)));
        // call back from coordinator
        vrfCoordinator.callBackWithRandomness(requestId, randomness, address(randProvider));
        gobblers.revealGobblers(numReveal);
    }

    function setUp() public {
        //
        utils = new Utilities();
        users = utils.createUsers(5);
        linkToken = new LinkToken();
        vrfCoordinator = new VRFCoordinatorMock(address(linkToken));

        // Gobblers contract will be deployed after 4 contract deploys, and pages after 5.
        address gobblerAddress = utils.predictContractAddress(address(this), 4);
        address pagesAddress = utils.predictContractAddress(address(this), 5);

        team = new GobblerReserve(ArtGobblers(gobblerAddress), address(this));
        community = new GobblerReserve(ArtGobblers(gobblerAddress), address(this));
        randProvider = new ChainlinkV1RandProvider(
            ArtGobblers(gobblerAddress),
            address(vrfCoordinator),
            address(linkToken),
            keyHash,
            fee
        );

        goo = new Goo(
        // Gobblers:
            utils.predictContractAddress(address(this), 1),
        // Pages:
            utils.predictContractAddress(address(this), 2)
        );

        gobblers = new ArtGobblers(
            keccak256(abi.encodePacked(users[0])),
            block.timestamp,
            goo,
            Pages(pagesAddress),
            address(team),
            address(community),
            randProvider,
            "base",
            "",
            keccak256(abi.encodePacked("provenance"))
        );

        pages = new Pages(block.timestamp, goo, address(0xBEEF), gobblers, "");
        goober = new Goober(address(gobblers), address(goo), address(this), address(this));
        // Setup approvals
        goo.approve(address(goober), type(uint256).max);
        gobblers.setApprovalForAll(address(goober), true);
    }

    function test_proxy() public {
        // Assertions
        assertEq(goober.name(), "Goober");
        assertEq(goober.symbol(), "GBR");
        assertEq(goober.decimals(), 18);
    }

    function testMintRevertCaller() public {
        vm.startPrank(msg.sender);
        //Revert if not Minter.
        vm.expectRevert();
        goober.mintGobbler();
        vm.stopPrank();
    }

    function test_mint() public {
        // Safety check to verify starting gobblerPrice is correct.
        assertEq(gobblers.gobblerPrice(), 73013654753028651285);

        // Add enough Goo to vault to mint a single Gobbler.
        _writeTokenBalance(address(this), address(goo), 1000 ether);

        uint256[] memory artGobbler = new uint256[](1);
        artGobbler[0] = gobblers.mintFromGoo(75 ether, false);
        // Check to see we own the 1st Gobbler.
        assertEq(gobblers.ownerOf(1), address(this));
        // Warp a day ahead until we can reveal.
        vm.warp(block.timestamp + 86400);
        setRandomnessAndReveal(1, "seed");
        uint256 gobblerMult = (gobblers.getGobblerEmissionMultiple(artGobbler[0]));
        // Based on our seed, we get a mult of 9 here.
        assertEq(gobblerMult, 9);

        // Pool is setup by depositing 1 gobbler and 53 goo.
        // We do this after warp to not accrue extra goo.
        uint256 gooTokens = 53 ether;
        address me = address(this);
        goober.deposit(artGobbler, gooTokens, me);

        // Safety check to verify new mint price after warp.
        assertEq(gobblers.gobblerPrice(), 52987405899699731484);

        // Now we have pool goo = 53 and pool mult = 9.
        // The goo/mult of our pool is <= goo/mult of the auction,
        // since: 53 / 9 = 5 <= 52.987 / 7.3294 ~= 7.
        // We also have enough goo to mint a single gobbler.
        // NOTE(Getting both of the aboveto be true is a very delicate
        // balance, especially tricky if you want to test minting
        // more than 1 gobbler here.)
        goober.mintGobbler();
        // Check contract owns second minted gobbler.
        assertEq(gobblers.ownerOf(2), address(goober));

        // Check to see updated pool balance after reveal.
        vm.warp(block.timestamp + 86400);
        // Changing the seed string changes the randomness, and thus the rolled mult.
        setRandomnessAndReveal(1, "seed2");
        // _newGobblerReserve is scaled up by 1e3
        (uint112 _newGooReserve, uint112 _newGobblerReserve,) = goober.getReserves();
        // We mint an 6 mult here, so we have 15 total mult including the previous 9.
        assertEq(_newGobblerReserve, 15000);
        // 24.9926 Goo
        assertEq(_newGooReserve, 2599264417825316518);

        // TODO(Check k)
    }

    function test_swap() public {
        _writeTokenBalance(address(this), address(goo), 2000 ether);
        gobblers.addGoo(500 ether);
        uint256[] memory artGobblers = new uint256[](2);
        uint256[] memory artGobblersTwo = new uint256[](1);
        uint256[] memory artGobblersThree = new uint256[](1);
        artGobblers[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblers[1] = gobblers.mintFromGoo(100 ether, true);
        artGobblersTwo[0] = gobblers.mintFromGoo(100 ether, true);
        artGobblersThree[0] = artGobblers[0];
        vm.warp(block.timestamp + 172800);
        setRandomnessAndReveal(3, "seed");
        uint256 gooTokens = 200 ether;
        address me = address(this);
        uint256 shares = goober.deposit(artGobblers, gooTokens, me);

        bytes memory data;
        IGoober.SwapParams memory swap =
            IGoober.SwapParams(artGobblersThree, 0 ether, artGobblersTwo, 100 ether, me, data);
        goober.swap(swap);

        shares = goober.withdraw(artGobblersTwo, 100 ether, me, me);
    }

    function test_skimGoo() public {
        _writeTokenBalance(address(goober), address(goo), 1);
        assertEq(goo.balanceOf(address(this)), 0);
        assertEq(goo.balanceOf(address(goober)), 1);
        //Revert if not owner.
        vm.startPrank(msg.sender);
        // vm.expectRevert(abi.encodeWithSelector(goober.AccessControlViolation.selector, msg.sender, address(this) ) );
        vm.expectRevert();
        goober.skimGoo();
        assertEq(goo.balanceOf(address(this)), 0);
        assertEq(goo.balanceOf(address(goober)), 1);
        vm.stopPrank();
        //Pass.
        goober.skimGoo();
        assertEq(goo.balanceOf(address(this)), 1);
        assertEq(goo.balanceOf(address(goober)), 0);
        //Revert when no goo in goobler contract.
        vm.expectRevert(IGoober.NoSkim.selector);
        goober.skimGoo();
    }
}
