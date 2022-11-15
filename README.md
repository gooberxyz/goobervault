# Goober Vault


![ci](https://github.com/gooberxyz/goobervault/actions/workflows/CI.yml/badge.svg)
[![codecov](https://codecov.io/gh/gooberxyz/goobervault/branch/main/graph/badge.svg?token=R24WD80X6N)](https://codecov.io/gh/gooberxyz/goobervault)

A special flavor of Uniswap V2 meets EIP-4626 to form a yield optimized Goo/Gobbler vault.

A full implementation and motivation can be found [here](https://docs.goober.xyz/).

## Background

Goober allows a user to effectively pool their Goo and/or Gobblers with other users, such that they all recieve more Goo emissions together than they would on their own. 

In order to keep `Goober` balanced and optimized (given the rate of Goo growth = `sqrt(goo * mult)`), the pool follows a CFMM curve akin to Uni V2's `x * y = k`, where `x` is the amount of `goo`, `y` is the amount of Gobbler `mult` and `k` represents the Goo growth per day of the pool. 


With Uni V2, the area under the bonding curve represents the liquidity (optimal distribution of each asset), and so maximizing it yields lower slippage. With Goober, the area under the bonding represents the optimal distribution of Goo and Gobbler in the pool's "tank", and so maximizing it yields the highest rate of Goo growth (`ΔK`) given the pool's reserves of `goo` and `mult`. 

As with Uni V2, that point of maximization happens to be at the point where `X` = `Y`, or in the case of Goober, where `goo` = `mult`. 

<img width="583" alt="Screen Shot 2022-11-14 at 4 50 03 PM" src="https://user-images.githubusercontent.com/94731243/201802003-d8583ddd-3799-48d1-a02d-3e4976005f64.png">

## Core Interface 

`Goober` exposes 3 core public functions: `deposit`, `withdraw`, and `swap`; which in conjunction with eachother, allow the market to optimize the ratio of `goo`/`mult` to increase `K` whilst dealing with market conditions. 

### deposit()

Depositing Goo or Goblers into `Goober` pool returns `fractions` (GBR - the pool's native token) to the depositor, dependant on the amount by which their deposit increases `K`. 

Thus, depositors are incentivized to maintain the balance of the pool's reserves, since by maximizing `ΔK`, they maximize the `fractions` returned by their deposit. 

### withdraw()

// TODO

### swap()

// TODO

## Internal 

### mintGobbler()

// TODO

### _update()

// TODO

## Deployments


| Contract      | Mainnet                                                                                                                 | Goerli                                                                                                                         |
|---------------|-------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| `Goober`      | [`0x2275d4937b6bFd3c75823744d3EfBf6c3a8dE473`](https://etherscan.io/address/0x2275d4937b6bfd3c75823744d3efbf6c3a8de473) | ❌


### Run Tests

In order to run unit tests, run:

```sh
forge test
```

For longer fuzz campaigns, run:

```sh
FOUNDRY_PROFILE="intense" forge test
```

### Run Slither

After [installing Slither](https://github.com/crytic/slither#how-to-install), run:

```sh
slither src/ --solc-remaps 'ds-test/=lib/ds-test/src/ solmate/=lib/solmate/src/ forge-std/=lib/forge-std/src/ chainlink/=lib/chainlink/contracts/src/ VRGDAs/=lib/VRGDAs/src/ goo-issuance/=lib/goo-issuance/src/'
```


### Update Gas Snapshots

To update the gas snapshots, run:

```sh
forge snapshot
```

