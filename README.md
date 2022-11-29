<a href="https://goober.xyz" target="_blank"><img src="https://user-images.githubusercontent.com/94731243/202322792-51390670-d6e0-466d-8c8d-457dc2d4dde6.png" alt="Goober"/></a> <a href="https://goober.xyz" target="_blank">dot xyz</a>

# Goober Vault

![ci](https://github.com/gooberxyz/goobervault/actions/workflows/CI.yml/badge.svg)
[![codecov](https://codecov.io/gh/gooberxyz/goobervault/branch/main/graph/badge.svg?token=R24WD80X6N)](https://codecov.io/gh/gooberxyz/goobervault)

A special flavor of Uniswap V2 meets EIP-4626 to form a yield optimized 
vault for Art Gobblers.

## Abstract

[Art Gobblers](https://artgobblers.com/) was constructed using two new innovations, [GOO](https://www.paradigm.xyz/2022/09/goo) (an emission mechanism) and [VRGDA](https://www.paradigm.xyz/2022/08/vrgda) (a Dutch auction mechanism). Gobblers continuously produce Goo, an ERC20 token, proportional to their multiplier and how much Goo is already in their "tank", a balance held per Ethereum address.

[Goober](https://goober.xyz) is a yield-optimized farm and liquidity engine for Goo and Gobblers. Goober allows a user to effectively pool their Goo and/or Gobblers with other users, such that they all receive more Goo emissions together than they would on their own, allowing market forces to maintain the optimal ratio of Goo/Gobblers in the pool. A unique flavor of of Uniswap V2 and EIP-4626 forms a special purpose AMM with vault-like characteristics and unique minting mechanics. Aside from bonding an ERC20 with an ERC721, Goober diverges from Uni-V2 via its internal bonding maintenance mechanics. The vault can mint new Gobblers when it’s profitable to do so under calculated contraints from the constant product formula and pool reserves, increasing the rate of future Goo emissions whilst continuing to keeping the pool balanced. 

Through Goober users can permissionlessly swap Gobblers and Goo, as well as deposit Goo and fractionalize their Gobblers in order to maximize their Goo accrual without the need for active management. By depositing Gobblers and/or Goo into the vault, users receive GBR in return, an ERC20 token that gives depositors claim to the assets in the vault.

![](https://i.imgur.com/LEUdsyV.png)

## Motivation

The Gobblers economy in its current form inherently converges towards a monopolization of resources. Since early, well funded actors possess the most Gobblers, they produce the most Goo, in turn continuously driving the price of the auction beyond any new entrants' reach - at a [quadratically](https://www.paradigm.xyz/2022/09/goo#:~:text=following%20differential%20equation%3A-,Solving%20it%20yields,-and%20expanding%2C%20we) increasing rate. Thus, a user with one or two Gobblers who has just gotten involved will likely never be able to mint another Gobbler with their Goo holdings.

Compounded by the fact that there is also low liquidity for Goo across decentralized exchanges, this dynamic makes it even more difficult for the average user to get the Goo flywheel turning without owning a Gobbler themselves. It has also caused large holders to mint from auction at an irrationally high Goo cost compared to the outstanding Goo supply. Since Gobbler prices on secondary markets inherently trade at a premium to the auction price, the average user has been effectively boxed out of the game.

## Mechanism

Utilizing an amalgamation of Uniswap V2's constant function market math, an ERC4626 yield-bearing vault (with GBR as the vault token), and automated VRGDA minting (using probabilistic computation compared to internal pricing) Goober aligns incentives to create an optimal balance of Goo and Gobbler multiplier for increased liquidity and Goo production across market conditions.

Since Art Gobblers NFTs produce Goo according to the formula: 

$$\sqrt{Goo * Mult} = GooProduction$$

The rate of growth of Goo happens to be maximized when Goo = Mult. There is an evident comparison with Uniswap v2's $x * y = k$ constant product market maker design, where the point of maximization is also the point at which $X = Y$.

Thus, Goober optimizes $+Δk$ for $x+y$ 
using an $x*y=k$ constant function market maker, where $$x=Goo$$ $$y=Mult$$ 
$$k={Goo * Mult}$$ $$\sqrt{k}=GooProduction$$

![](https://i.imgur.com/QSd4PE2.png)

## Resources

Documentation can be found [here](https://goober.xyz).

## Deployments

| Contract      | Mainnet                                                                                                                 |                 
|---------------|-------------------------------------------------------------------------------------------------------------------------|
| `Goober`      | [`0x2275d4937b6bFd3c75823744d3EfBf6c3a8dE473`](https://etherscan.io/address/0x2275d4937b6bfd3c75823744d3efbf6c3a8de473) |

## Developer Guide

### Running Tests

[Install Foundry](https://github.com/foundry-rs/foundry/tree/master/foundryup)

In order to run unit tests, run:

```sh
forge install
forge test
```

For longer fuzz campaigns, run:

```sh
FOUNDRY_PROFILE="intense" forge test
```

### Running Slither

After installing [Poetry](https://python-poetry.org/docs/#installing-with-the-official-installer) and [Slither](https://github.com/crytic/slither#how-to-install) run:
[Slither on Apple Silicon](https://github.com/crytic/slither/issues/1051)
```sh
poetry install
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

## License

[MIT](https://github.com/gooberxyz/goobervault/blob/master/LICENSE) © 2022 Goober

