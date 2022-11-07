// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "art-gobblers/Goo.sol";
import "../src/Goober.sol";
import "art-gobblers/../test/utils/mocks/LinkToken.sol";
import {Utilities} from "art-gobblers/../test/utils/Utilities.sol";
import "art-gobblers/../lib/chainlink/contracts/src/v0.8/mocks/VRFCoordinatorMock.sol";
import {ChainlinkV1RandProvider} from "art-gobblers/utils/rand/ChainlinkV1RandProvider.sol";
import "art-gobblers/utils/GobblerReserve.sol";
import "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";

contract TestUERC20Functionality is Test, IERC721Receiver {
    using stdStorage for StdStorage;

    // Test Contracts
    Goober public goober_implementation;
    TransparentUpgradeableProxy public goober_proxy;
    IGoober public goober;

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

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4)
    {
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
        goober_implementation = new Goober();
        goober_proxy =
        new TransparentUpgradeableProxy(address(goober_implementation), address(msg.sender), abi.encodeWithSignature("initialize(address,address)", gobblerAddress, address(goo)));
        goober = IGoober(address(goober_proxy));
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
        uint256 shares = goober.deposit(artGobblers, gooTokens, me, me);
        bytes memory data;
        IGoober.SwapParams memory swap =
            IGoober.SwapParams(artGobblersThree, 0 ether, artGobblersTwo, 103 ether, me, me, data);
        goober.swap(swap);
        // TODO(Get this working)
        shares = goober.withdraw(artGobblersTwo, gooTokens, me, me);
    }
}
