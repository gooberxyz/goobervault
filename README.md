# Goober Vault


![ci](https://github.com/gooberxyz/goobervault/actions/workflows/CI.yml/badge.svg)
[![codecov](https://codecov.io/gh/gooberxyz/goobervault/branch/main/graph/badge.svg?token=R24WD80X6N)](https://codecov.io/gh/gooberxyz/goobervault)

A special flavor of Uniswap V2 meets EIP-4626 to form a yield optimized 
vault for Art Gobblers.

## Abstract

Art Gobblers is an experimental, decentralized, art factory using two new 
innovations, [GOO](https://www.paradigm.xyz/2022/09/goo) and 
[VRGDA](https://www.paradigm.xyz/2022/08/vrgda). Art Gobblers NFTs produce 
Goo according to this formula: $\sqrt{Goo * Mult}=Goo per day$

Goober allows a user to effectively pool their Goo and/or Gobblers with other 
users, such that they all receive more Goo emissions together than they would 
on their own.

The point of maximization for $\sqrt{x * y}$ happens to be at the point where 
$x=y$. However, due to market forces, that may not always be the point with 
the highest yield in outside terms. Thus, Goober optimizes $Δk$ for $x+y$ 
using an $x*y=k$ constant function market maker, where $x=Goo$, $y=Mult$, 
and $k=Goo per day$, allowing market forces to maintain the optimal 
ratio of Goo/Gobblers in the pool. 

<img width="583" alt="Screen Shot 2022-11-14 at 4 50 03 PM" src="https://user-images.githubusercontent.com/94731243/201802003-d8583ddd-3799-48d1-a02d-3e4976005f64.png">

Goober additionally uses this market to optimally mint new Gobblers to 
the pool using probabilistic pricing per gobbler multiplier compared to
the pool's internal pricing.

## Resources

Documentation can be found [here](https://docs.goober.xyz/).

## Deployments

| Contract      | Mainnet                                                                                                                 |                                                                                                                         |
|---------------|-------------------------------------------------------------------------------------------------------------------------|
| `Goober`      | [`0x2275d4937b6bFd3c75823744d3EfBf6c3a8dE473`](https://etherscan.io/address/0x2275d4937b6bfd3c75823744d3efbf6c3a8de473) |

## Developer Guide

### Running Tests

In order to run unit tests, run:

```sh
forge test
```

For longer fuzz campaigns, run:

```sh
FOUNDRY_PROFILE="intense" forge test
```

### Running Slither

After installing poetry, run:

```sh
poetry intstall
poetry shell
slither src/Goober.sol --config-file slither.config.json
```


### Updating Gas Snapshots

To update the gas snapshots, run:

```sh
forge snapshot
```

### Generating Coverage Report

To see project coverage, run:

```shell
forge coverage
```

