pragma solidity >=0.8.0;

import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";

interface IGoober is IERC20Metadata, IERC721Receiver {
    function deposit(uint256[] calldata gobblers, uint256 gooTokens, address owner, address receiver)
        external
        returns (uint256 shares);

    function withdraw(uint256[] calldata gobblers, uint256 gooTokens, address receiver, address owner)
        external
        returns (uint256 shares);

    function swap(uint256[] calldata gobblers, uint256 gooTokens, address receiver, bytes calldata data) external;
}
