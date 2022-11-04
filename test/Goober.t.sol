// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "art-gobblers/Goo.sol";
import "art-gobblers/ArtGobblers.sol";
import "../src/Goober.sol";
import "../src/interfaces/IERC3156FlashBorrower.sol";

contract TestUERC20Functionality is Test, IERC3156FlashBorrower {
    using stdStorage for StdStorage;

    // Test Contracts
    Goober public goober_implementation;
    TransparentUpgradeableProxy public goober_proxy;
    
    // Art gobbler stuff
    Goo public constant goo = Goo(0x600000000a36F3cD48407e35eB7C5c910dc1f7a8);
    ArtGobblers public constant artGobblers = ArtGobblers(0x60bb1e2AA1c9ACAfB4d34F71585D7e959f387769);

    address public constant GOBBLER_WHALE = 0x0c1a3E4E1C3DA4c89582dfA1AFA87A1853D7f78f;
    address public constant GOO_WHALE = 0x52c7bDbE5093d4EdB47C917Bf6d148FF41B72EE9;
    

    function setUp() public {
        goober_implementation = new Goober();
        goober_proxy =
        new TransparentUpgradeableProxy(address(goober_implementation), address(msg.sender), abi.encodeWithSignature("initialize()"));
        goo.approve(address(goober_proxy), type(uint256).max);
        // set 5% fee
        Goober(address(goober_proxy)).changeFee(500);
    }

    function test_proxy() public {
        // Assertions
        assertEq(IERC20Metadata(address(goober_proxy)).name(), "Goober");
        assertEq(IERC20Metadata(address(goober_proxy)).symbol(), "GBR");
        assertEq(IERC20Metadata(address(goober_proxy)).decimals(), 18);
    }

    function test_flashloan() public {
        // put some gobblers and goo into the Goober contract
        uint256[] memory GOBBLER_IDS = new uint256[](6);
        GOBBLER_IDS[0] = 1271;
        GOBBLER_IDS[1] = 116;
        GOBBLER_IDS[2] = 1091;
        GOBBLER_IDS[3] = 1905;
        GOBBLER_IDS[4] = 1896;
        GOBBLER_IDS[5] = 1898;
        vm.startPrank(GOBBLER_WHALE);
        for (uint256 i = 0; i < 6; i++) {
            artGobblers.transferFrom(GOBBLER_WHALE, address(goober_proxy), GOBBLER_IDS[i]);
        }
        vm.stopPrank();
        
        vm.startPrank(GOO_WHALE);
        goo.transfer(address(this), 1 ether);
        goo.transfer(address(goober_proxy), 16 ether);
        vm.stopPrank();
        vm.prank(address(goober_proxy));
        artGobblers.addGoo(16 ether);

        // execute flashloan
        Goober(address(goober_proxy)).flashLoan(IERC3156FlashBorrower(address(this)), address(goo), 10 ether, "");

        // TODO make sure the accounting adds up
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
