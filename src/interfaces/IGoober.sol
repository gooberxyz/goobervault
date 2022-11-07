pragma solidity >=0.8.0;

import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";

interface IGoober is IERC20Metadata, IERC721Receiver {
    // Structs

    struct SwapParams {
        uint256[] gobblersOut;
        uint256 gooOut;
        uint256[] gobblersIn;
        uint256 gooIn;
        address owner;
        address receiver;
        bytes data;
    }

    // EVENTS

    event Deposit(
        address indexed caller,
        address indexed owner,
        address indexed receiver,
        uint256[] gobblers,
        uint256 gooTokens,
        uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256[] gobblers,
        uint256 gooTokens,
        uint256 shares
    );

    event Swap(
        address indexed sender,
        uint256 gooTokensIn,
        uint256 gobblersMultIn,
        uint256 gooTokensOut,
        uint256 gobblerMultOut,
        address indexed receiver
    );

    event Sync(uint112 gooBalance, uint112 multBalance);

    function deposit(uint256[] calldata gobblers, uint256 gooTokens, address owner, address receiver)
        external
        returns (uint256 shares);

    function withdraw(uint256[] calldata gobblers, uint256 gooTokens, address receiver, address owner)
        external
        returns (uint256 shares);

    function swap(SwapParams calldata params) external;
}
