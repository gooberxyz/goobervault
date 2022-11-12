# Goober Vault


![ci](https://github.com/gooberxyz/goobervault/actions/workflows/CI.yml/badge.svg)
[![codecov](https://codecov.io/gh/gooberxyz/goobervault/branch/main/graph/badge.svg?token=R24WD80X6N)](https://codecov.io/gh/gooberxyz/goobervault)

A special flavor of Uniswap V2 meets EIP-4626 to form a yield optimized goo/gobbler vault.

## Anvil Setup



Start anvil:

anvil --fork-url ETH_RPC --fork-block-number 15900776 --chain-id 31337

Run bash script:

./setup.sh

This transfers a Gobbler and 1 GOO to the address that will deploy the Goober contract, and then 5 GOO and 6 different Gobblers to the first unlocked Anvil wallet (0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266).

Run the anvil script to deploy the Goober contract:

forge script script/DeployGoober.s.sol:DeployGooberScript --broadcast --fork-url http://localhost:8545 --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

Now you can import the private key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 to Metamask or other wallet of choice and visit localhost:3071.

Goober is deployed with the 2nd unlocked anvil wallet.

