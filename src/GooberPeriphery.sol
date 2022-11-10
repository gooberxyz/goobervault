// SPDX-License-Identifier: MIT
// TODO(Should this be BUSL?)

pragma solidity ^0.8.17;

import "./Goober.sol";

interface IGooberPeriphery {
    function deposit(
        uint256[] calldata gobblers,
        uint256 gooTokens,
        address receiver,
        uint256 minFractionsOut,
        uint256 deadline
    ) external returns (uint256 fractions);
}

contract GooberPeriphery {
    Goober public immutable goober;

    constructor(address _gooberAddress) {
        goober = Goober(_gooberAddress);

        goober.artGobblers().setApprovalForAll(address(goober), true);
        goober.goo().approve(address(goober), type(uint256).max);
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "GooberPeriphery: EXPIRED");
        _;
    }

    /*//////////////////////////////////////////////////////////////
    // External: Non Mutating
    //////////////////////////////////////////////////////////////*/

    /// @notice Handle deposits of Art Gobblers with an on receive hook, verifying characteristics.
    /// @dev We don't accept non art gobbler NFTs, Art Gobblers with invalid multiples.
    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external view returns (bytes4) {
        /// @dev We only want Art Gobblers NFTs
        if (msg.sender != address(goober.artGobblers())) {
            revert IGoober.InvalidNFT();
        }

        // TODO: Do we need this here?
        /// @dev revert on flagged NFTs
        // if (flagged[tokenId] == true) {
        //     revert InvalidNFT();
        // }

        /// @dev We want to make sure the gobblers we are getting are revealed.
        uint256 gobMult = goober.artGobblers().getGobblerEmissionMultiple(tokenId);
        if (gobMult < 6) {
            revert IGoober.InvalidMultiplier(tokenId);
        }

        return IERC721Receiver.onERC721Received.selector;
    }

    function deposit(
        uint256[] calldata gobblers,
        uint256 gooTokens,
        address receiver,
        uint256 minFractionsOut,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 fractionsOut) {
        goober.goo().transferFrom(msg.sender, address(this), gooTokens);

        for (uint256 i = 0; i < gobblers.length; i++) {
            goober.artGobblers().safeTransferFrom(msg.sender, address(this), gobblers[i]);
        }

        fractionsOut = goober.deposit(gobblers, gooTokens, receiver);

        require(fractionsOut >= minFractionsOut, "GooberPeriphery: INSUFFICIENT_LIQUIDITY_MINTED");
    }

    function withdraw(
        uint256[] calldata gobblers,
        uint256 gooTokens,
        address receiver,
        address owner,
        uint256 maxFractionsIn,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 fractionsIn) {
        fractionsIn = goober.withdraw(gobblers, gooTokens, receiver, owner);

        require(fractionsIn <= maxFractionsIn, "GooberPeriphery: BURN_ABOVE_LIMIT");
    }

    function swap(Goober.SwapParams calldata parameters, int256 erroneousGooAbs, uint256 deadline)
        external
        ensure(deadline)
        returns (int256 erroneousGoo)
    {
        erroneousGoo = goober.swap(parameters);

        require(erroneousGoo <= erroneousGooAbs, "GooberPeriphery: EXCESSIVE_INPUT_AMOUNT");
    }
}
