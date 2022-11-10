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

    function test_mint_revert_caller() public {
        vm.startPrank(msg.sender);
        //Revert if not Minter.
        vm.expectRevert();
        goober.mintGobbler();
        vm.stopPrank();
    }

    function test_mint_revert_goo() public {
        // Safety check to verify starting gobblerPrice is correct.
        assertEq(gobblers.gobblerPrice(), 73013654753028651285);

        // Add enough goo to vault to mint one gobbler.
        _writeTokenBalance(address(this), address(goo), 1000 ether);

        // Mint the first gobbler
        uint256[] memory artGobbler = new uint256[](1);
        artGobbler[0] = gobblers.mintFromGoo(75 ether, false);

        // Safety check to verify new VRGDA price after first mint.
        assertEq(gobblers.gobblerPrice(), 76793341883622799170);

        // Warp a day ahead until we can reveal Gobbler 1.
        vm.warp(block.timestamp + 86400);
        setRandomnessAndReveal(1, "seed");
        uint256 gobblerMult = (gobblers.getGobblerEmissionMultiple(artGobbler[0]));
        // Based on our seed, we get a mult of 9 here.
        assertEq(gobblerMult, 9);

        // Safety check to verify new VRGDA price after first mint and warp.
        assertEq(gobblers.gobblerPrice(), 52987405899699731484);

        // Pool is setup by depositing 1 gobbler (9 mult) and 20 goo.
        // We make goo virtual after warp to not accrue extra goo.
        uint256 gooTokens = 20 ether;
        address me = address(this);
        goober.deposit(artGobbler, gooTokens, me);
        gobblers.addGoo(20 ether);

        // Tries to mint a gobbler, should revert due to
        // insufficient goo balance.
        // TODO(Add custom event emit for this and test it)
        vm.expectRevert(bytes("Pool Goo per Mult lower than Auction's"));
        goober.mintGobbler();
    }

    function test_mint_revert_ratio() public {
        // Safety check to verify starting gobblerPrice is correct.
        assertEq(gobblers.gobblerPrice(), 73013654753028651285);

        // Add enough goo to vault to mint two gobblers.
        _writeTokenBalance(address(this), address(goo), 1000 ether);

        // Mint the first gobbler
        uint256[] memory artGobblers = new uint256[](2);
        artGobblers[0] = gobblers.mintFromGoo(75 ether, false);
        // Check to see we own the 1st gobbler.
        assertEq(gobblers.ownerOf(1), address(this));
        // Warp a day ahead until we can reveal Gobbler 1.
        vm.warp(block.timestamp + 86400);
        setRandomnessAndReveal(1, "seed");
        uint256 gobblerMult = (gobblers.getGobblerEmissionMultiple(artGobblers[0]));
        // Based on our seed, we get a mult of 9 here.
        assertEq(gobblerMult, 9);

        // Safety check to verify new VRGDA price after first mint and warp.
        assertEq(gobblers.gobblerPrice(), 52987405899699731484);

        // Mint a second gobbler
        artGobblers[1] = gobblers.mintFromGoo(55 ether, false);

        // Warp a day ahead until we can reveal gobbler 2.
        vm.warp(block.timestamp + 86400);
        setRandomnessAndReveal(1, "seed2");
        uint256 gobbler2Mult = (gobblers.getGobblerEmissionMultiple(artGobblers[1]));
        // Based on our seed, we get a mult of 6 here.
        assertEq(gobbler2Mult, 6);

        // Safety check to verify new VRGDA price after second mint and warp.
        assertEq(gobblers.gobblerPrice(), 38453974223663505198);

        // Pool is setup by depositing 2 gobblers (15 mult) and 60 goo.
        // We make goo virtual after warp to not accrue extra goo.
        uint256 gooTokens = 60 ether;
        address me = address(this);
        goober.deposit(artGobblers, gooTokens, me);
        gobblers.addGoo(60 ether);

        // Try mint and expect the first revert message
        // since 60 / 15 < 38.45 / 7.32, implying the pool is not
        // imbalanced enough to mint and the revert confirms
        // that we don't reach the while loop.
        vm.expectRevert(bytes("Pool Goo per Mult lower than Auction's"));
        goober.mintGobbler();
    }

    function test_mint() public {
        // TODO(Test minting 3 or more gobblers at once)

        // Safety check to verify starting gobblerPrice is correct.
        assertEq(gobblers.gobblerPrice(), 73013654753028651285);

        // Add enough Goo to vault to mint a single Gobbler.
        _writeTokenBalance(address(this), address(goo), 1000 ether);

        // Mint the first Gobbler
        uint256[] memory artGobbler = new uint256[](1);
        artGobbler[0] = gobblers.mintFromGoo(75 ether, false);
        // Check to see we own the first Gobbler
        assertEq(gobblers.ownerOf(1), address(this));
        // Warp a day ahead until we can reveal Gobbler 1.
        vm.warp(block.timestamp + 86400);
        setRandomnessAndReveal(1, "seed");
        uint256 gobblerMult = (gobblers.getGobblerEmissionMultiple(artGobbler[0]));
        // Based on our seed, we get a mult of 9 here.
        assertEq(gobblerMult, 9);

        // Pool is setup by depositing 1 gobbler and 53 goo.
        // We do this after warp to not accrue extra goo.
        uint256 gooTokens = 81 ether;
        address me = address(this);
        goober.deposit(artGobbler, gooTokens, me);
        // Make the goo virtual, since that's what we mint with.
        gobblers.addGoo(81 ether);

        // Safety check to verify new mint price after warp.
        assertEq(gobblers.gobblerPrice(), 52987405899699731484);

        // Now we have pool goo = 81 and pool mult = 9.
        // The goo/mult of our pool is <= goo/mult of the auction,
        // since: 81 / 9 = 9 >= 52.987 / 7.3294 ~= 7.
        // We also have enough goo to mint a single gobbler.
        // NOTE(Getting both of the above to be true is a very delicate
        // balance, especially tricky if you want to test minting
        // more than 1 gobbler here).

        // Mint a gobbler, and check we return 1 (gobbler) minted.
        // NOTE(Updates K, reserves and VRGDA in the process.)
        assertEq(goober.mintGobbler(), 1);

        (uint112 _GooReserve, uint112 _GobblerReserve,) = goober.getReserves();
        // Check our Goo balance went down from minting: 81 - 52.99 ~= 28.01.
        assertEq(_GooReserve, 28012594100300268516);

        // Warp ahead to reveal second gobbler.
        vm.warp(block.timestamp + 86400);
        // Changing the seed string changes the randomness, and thus the rolled mult.
        setRandomnessAndReveal(1, "seed2");

        // Check contract owns second minted gobbler.
        assertEq(gobblers.ownerOf(2), address(goober));

        // Check to see updated pool balance after reveal.

        (uint112 _newGooReserve, uint112 _newGobblerReserve,) = goober.getReserves();
        // Check we have 15 total mult including the previous 9, since we minted a 6.
        assertEq(_newGobblerReserve, 15);
        // Check our goo balance updated from emission.
        assertEq(_newGooReserve, 46140671657193055549);

        // NOTE(Checking k uneeded since _update() handles all of that
    }

    // function test_withdraw_minted() public {
    // Test if we can pull a minted Gobbler out of pool)
    // TODO(You must deposit and mint shares first before withdrawing).

    // uint256[] memory artGobblerFromMint = new uint256[](1);

    //  Gobbler with tokenId = 2.
    // artGobblerFromMint[0] = 2;
    // address me = address(this);
    //  Withdraw Gobbler minted from Goober based on shares minted from kDebt.
    // goober.withdraw(artGobblerFromMint, 0, me, me);

    // Check if we own the Gobbler now.
    // assertEq(gobblers.ownerOf(2), me);
    // }

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
