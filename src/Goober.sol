// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./utils/Initializable.sol";
import "./proxy/UUPSUpgradeable.sol";
import "./utils/Ownable.sol";
import "./tokens/ERC20.sol";
import "./security/Pausable.sol";
import "./security/ReentrancyGuard.sol";

contract Goober is Initializable, UUPSUpgradeable, Ownable, Pausable, ReentrancyGuard, ERC20 {
    constructor() initializer {}

    function initialize() public initializer {
        __ERC20_init("Goober", "GBR");
        __ReentrancyGuard_init(); // @dev as there is no constructor, we need to initialise the ReentrancyGuard explicitly
        __Pausable_init(); // @dev as there is no constructor, we need to initialise the Pausable explicitly
        __Ownable_init(); // @dev as there is no constructor, we need to initialise the Ownable explicitly
    }

    // @dev required by the UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     */
    uint256[50] private __gap;
}
