# Goober Vault


![ci](https://github.com/gooberxyz/goobervault/actions/workflows/CI.yml/badge.svg)
[![codecov](https://codecov.io/gh/gooberxyz/goobervault/branch/main/graph/badge.svg?token=R24WD80X6N)](https://codecov.io/gh/gooberxyz/goobervault)

A special flavor of Uniswap V2 meets EIP-4626 to form a yield optimized 
vault for Art Gobblers.

## Abstract

Art Gobblers is an experimental, decentralized, art factory using two new 
innovations, [Goo](https://www.paradigm.xyz/2022/09/goo) and 
[VRGDA](https://www.paradigm.xyz/2022/08/vrgda). Art Gobblers NFTs produce 
Goo according to this formula: $\sqrt{Goo * Mult}=GooProduction$

Goober allows a user to effectively pool their Goo and/or Gobblers with other 
users, such that they all receive more Goo emissions together than they would 
on their own.

The point of maximization for $\sqrt{x * y}$ happens to be at the point where 
$x=y$. However, due to market forces, that may not always be the point with 
the highest yield in outside terms. Thus, Goober optimizes $+Δk$ for $x+y$ 
using an $x*y=k$ constant function market maker, where $x=Goo$, $y=Mult$, 
$k={Goo * Mult}$  and $\sqrt{k}=GooProduction$, allowing market forces to 
maintain the optimal ratio of Goo/Gobblers in the pool while still 
maximizing $+ΔGooProduction$ and area of assets under the bonding curve. 


Since we want to optimize Goo emission, we want to incentivize increasing $K$ upon deposits. 

The total rate of emission of the vault is tracked by a constant $K$, where

$$
K = \sqrt{(Goo * Mult)}
$$


When a`deposit` is made to the pool, a new $n$ value of reserves is calculated based on the amount of each asset added by depositor $d$.

$$
Goo_{n} = Goo_{i} + Goo_{d} 
$$

and

$$
Mult_{n} = Mult_{i} + Mult_{d}
$$

Now that we have some increase in our emission

$$
{K}_{n} > K_{i}
$$

the depositor should be rewarded accordingly. Thus, the vault mints some amount of $F_{d}$ to transfer to the depositor, where 


$$
{ F }_{d}={ F }_{i} * {\sqrt{(Goo_{n} * Mult_{n})} - \sqrt{(Goo_{i} * Mult_{i})} \over \sqrt{(Goo_{i} * Mult_{i})}}
$$

which can be simplified to:

$$
{ F }_{d}={ F }_{i} * ({\sqrt{(Goo_{n} * Mult_{n})} \over \sqrt{(Goo_{i} * Mult_{i})}} -1)
$$

or even further:

$$
{ F }_{d}={ F }_{i} * \Delta K
$$

Since $\text {F}$ represents a fixed fraction of the pool. As the pool grows, so too will the assets redeemable by the fraction.

On `withdraw`, a user exchanges some $\text {F}$ for $Goo$ and/or $Mult$, burning the respective amount of $\text {F}$ in the process. 

Since, a withdrawal decreases the reserves, then post `withdraw`:

$$
{K}_{n} < K_{i}
$$

Since the pool's rate of $Goo$ emission has decreased, then so too must its supply of outstanding fractions by a proportionate amount.

We can derive the amount of reserves alloted to an amount of ${ F }_{d}$ from the inverse of the issuance calculation: 


$$
{ F }_{d}={ F }_{i} * ({\sqrt{(Goo_{w} * Mult_{w})} \over \sqrt{(Goo_{i} * Mult_{i})}} -1)
$$

which can be rearranged to


$$
{Goo_{w}} = {{(Goo_{i} * Mult_{i})}({{ F }_{d} \over { F }_{i}} + 1)^2 \over Mult_{w}} 
$$

Autonomous market forces keep the pool balanced, and thus producing the most goo per goo possible. 

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

## License

[MIT](https://github.com/gooberxyz/goobervault/blob/master/LICENSE) © 2022 Goober

