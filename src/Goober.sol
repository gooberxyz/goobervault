// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./utils/Initializable.sol";
import "./proxy/UUPSUpgradeable.sol";
import "./utils/Ownable.sol";
import "./tokens/ERC20Upgradable.sol";
import "./security/Pausable.sol";
import "./security/ReentrancyGuard.sol";
import "art-gobblers/Goo.sol";
import "art-gobblers/ArtGobblers.sol";
import "art-gobblers/Pages.sol";

contract Goober is Initializable, UUPSUpgradeable, Ownable, Pausable, ReentrancyGuard, ERC20Upgradable {
    // Events

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    // Constant/Immutable storage

    // TODO(Add casing for gorli deploy)
    Goo public constant goo = Goo(0x600000000a36F3cD48407e35eB7C5c910dc1f7a8);
    ArtGobblers public constant artGobblers = ArtGobblers(0x60bb1e2AA1c9ACAfB4d34F71585D7e959f387769);
    Pages public constant pages = Pages(0x600Df00d3E42F885249902606383ecdcb65f2E02);

    constructor() initializer {}

    function initialize() public initializer {
        __ERC20_init("Goober", "GBR");
        __ReentrancyGuard_init(); // @dev as there is no constructor, we need to initialise the ReentrancyGuard explicitly
        __Pausable_init(); // @dev as there is no constructor, we need to initialise the Pausable explicitly
        __Ownable_init(); // @dev as there is no constructor, we need to initialise the Ownable explicitly
    }

    // @dev required by the UUPS module
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // When our GOO balance exceeds M/Q * G at time t where M is the total multiple of our GOBBLER and Q is the
    // total multiple of all GOBBLER and G is the total supply of GOO we have too much goo in the tank.

    // When our GOO balance is less than M/Q * G at time t where M is the total multiple of our GOBBLER and Q is
    // the total multiple of all GOBBLER and G is the total supply of GOO we have too little goo in the tank.

    // When our GOO balance equals M/Q * G at time t where M is the total multiple of our GOBBLER and Q is the
    // total multiple of all GOBBLER and G is the total supply of GOO we have the right amount in the tank.

    // And, the events that can push us out of bounds are the deposit or withdraw of GOO/GOBBLER from
    // the vault, mint of new GOBBLER (changes Q) or burn of a gobber

    // TODO(Effect of legendary gobblers)
    // TODO(Pages)

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     */
    uint256[50] private __gap;
}
