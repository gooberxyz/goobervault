<a href="https://goober.xyz" target="_blank"><img src="https://user-images.githubusercontent.com/94731243/202322792-51390670-d6e0-466d-8c8d-457dc2d4dde6.png" alt="Goober"/></a> <a href="https://goober.xyz" target="_blank">dot xyz</a>

# Goober Vault

![ci](https://github.com/gooberxyz/goobervault/actions/workflows/CI.yml/badge.svg)
[![codecov](https://codecov.io/gh/gooberxyz/goobervault/branch/main/graph/badge.svg?token=R24WD80X6N)](https://codecov.io/gh/gooberxyz/goobervault)

A special flavor of Uniswap V2 meets EIP-4626 to form a yield optimized 
vault for Art Gobblers.

## Abstract

Art Gobblers is an experimental, decentralized, art factory using two new 
innovations, [Goo](https://www.paradigm.xyz/2022/09/goo) and 
[VRGDA](https://www.paradigm.xyz/2022/08/vrgda). Art Gobblers NFTs produce 
Goo according to the formula: 

$$\sqrt{Goo * Mult} = GooProduction$$

Goober allows a user to effectively pool their Goo and/or Gobblers with other 
users, such that they all receive more Goo emissions together than they would 
on their own, allowing market forces to maintain the optimal ratio of Goo/Gobblers in the pool.

The point of maximization for $\sqrt{x * y}$  happens to be at the point where 
$x=y$. However, due to market forces, that may not always be the point with 
the highest yield in outside terms. 

Thus, Goober optimizes $+Δk$ for $x+y$ 
using an $x*y=k$ constant function market maker, where $$x=Goo$$ $$y=Mult$$ 
$$k={Goo * Mult}$$ $$\sqrt{k}=GooProduction$$


To optimize tank Goo emission, the pool wants to incentivize increasing $k$ upon deposits. 

The total rate of emission of the vault is tracked by a constant $k$, where

$$
\sqrt{k} = \sqrt{(Goo * Mult)}
$$


When a `deposit` is made to the pool, a new $n$ value of reserves is calculated based on the amount of each asset added by depositor $d$, where

$$
Goo_{n} = Goo_{i} + Goo_{d} 
$$

and

$$
Mult_{n} = Mult_{i} + Mult_{d}
$$

Now that we have some increase in our emission

$$
k_{n} > k_{i}
$$

the depositor should be rewarded accordingly. Thus, the vault mints some amount of $F_{d}$ to transfer to the depositor, where 


$$
F_{d} = F_{i} * {\sqrt{(Goo_{n} * Mult_{n})} - \sqrt{(Goo_{i} * Mult_{i})} \over \sqrt{(Goo_{i} * Mult_{i})}}
$$

which can be simplified to

$$
F_{d} = F_{i} * ({\sqrt{(Goo_{n} * Mult_{n})} \over \sqrt{(Goo_{i} * Mult_{i})}} -1)
$$

or even further

$$
F_{d} = F_{i} * \Delta k
$$

Since $\text {F}$ represents a fixed fraction of the pool. As the pool grows, so too will the assets redeemable by the fraction. On `withdraw`, a user exchanges some $\text {f}$ for $Goo$ and/or $Mult$, burning the respective amount of $\text {F}$ in the process. 

Since, a withdrawal decreases the reserves, then post `withdraw` we have 

$$
k_{n} < k_{i}
$$

As the pool's rate of $Goo$ emission has decreased, then so too must its supply of outstanding fractions by a proportionate amount.
We can derive the amount of reserves alloted to an amount of $F_{d}$ from the inverse of the issuance calculation


$$
F_{d} = F_{i} * ({\sqrt{(Goo_{w} * Mult_{w})} \over \sqrt{(Goo_{i} * Mult_{i})}} -1)
$$

which can be rearranged to


$$
{Goo_{w}} = {{(Goo_{i} * Mult_{i})}({{ F }_{d} \over { F }_{i}} + 1)^2 \over Mult_{w}} 
$$

where $Goo_{w}$ and $Mult_{w}$ represent the respective reserves (each can be solved for interchangably) that can be withdrawn in tandem for some amount of fractions $F_{d}$.

Autonomous market forces keep the pool balanced, through the aligned incentives of maximizing $+Δk$, and thus producing the most goo per goo possible. This can be visualized as the area under the bonding curve of Goo and Mult:

<img width="583" alt="Screen Shot 2022-11-14 at 4 50 03 PM" src="https://user-images.githubusercontent.com/94731243/201802003-d8583ddd-3799-48d1-a02d-3e4976005f64.png">

Goober additionally uses this market to optimally mint new Gobblers to 
the pool using probabilistic pricing per gobbler multiplier compared to
the pool's internal pricing.

## Resources

Documentation can be found [here]().

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

