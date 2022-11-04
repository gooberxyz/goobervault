# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# deps
update:; forge update

# Build & test
build  :; forge build --sizes

t   :; forge test -vvv --rpc-url=${ETH_RPC_URL} --fork-block-number 15895231