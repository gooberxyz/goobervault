# Goober Litepaper

## Introduction

[Goober](https://goober.xyz) is a yield-optimized farm and liquidity engine for [Art Gobblers](https://artgobblers.com/), the experimental, decentralized art factory by Paradigm and Justin Roiland. Art Gobblers was constructed using two new innovations, [GOO](https://www.paradigm.xyz/2022/09/goo) (an emission mechanism) and [VRGDA](https://www.paradigm.xyz/2022/08/vrgda) (a Dutch auction mechanism). Gobblers continuously produce Goo, an ERC20 token, proportional to their multiplier and how much Goo is already in their "tank", a balance held per Ethereum address.

Built for the Art Gobblers ecosystem, Goober allows users to permissionlessly swap Gobblers and Goo, as well as deposit Goo and fractionalize their Gobblers in order to maximize their Goo accrual without the need for active management. By depositing Gobblers and/or Goo into the vault, users receive GBR in return, an ERC20 token that gives depositors claim to the assets in the vault.

## Motivation

Several months prior to the release of Art Gobblers, the Paradigm team reached out to Grug, now a member of the Goober team, with the goal of gathering a group of MEV searchers to battle test the Art Gobbler issuance mechanism. The Art Gobblers contracts were deployed on the Goerli testnet with parameters sped up 30x in order to simulate 2 years in 2 weeks.

The test imparted a great degree of knowledge about the VRGDA and GOO mechanisms underpinning Art Gobblers onto all the participants. Notably, that participants who did not hit the ground running early would stand little to no chance of keeping up their Goo accrual with those that did.

This has also been true in production — the existing Goo and  Gobbler distribution heavily favors those with deep pockets or who colluded early on. Since these actors possess the most Gobblers, they produce the most Goo, in turn continuously driving the price of the auction beyond any new entrants' reach - at a [quadratically](https://) increasing rate. Thus, a user with one or two Gobblers who has just gotten involved will likely never be able to mint another Gobbler with their Goo holdings.

Compounded by the fact that there is also low liquidity for Goo across decentralized exchanges, this dynamic makes it even more difficult for the average user to get the Goo flywheel turning without owning a Gobbler themselves. It has also caused large holders to mint from auction at an irrationally high Goo cost compared to the outstanding Goo supply. Since Gobbler prices on secondary markets inherently trade at a premium to the auction price, the average user has been effectively boxed out of the game.

## Solution

Both liquidity and the ability to effectively pool capital with other users are necessary to compete with the quadratic inflation of Goo in the Art Gobblers system. Additionally, determining an optimal minting strategy

It is very difficult to account for illiquidity and market fluctuations. In trying to solve for this, it became apparent that a constant function market maker optimizes for Goo production, it matches the shape of the function for optimal Goo production, and in fact, the unit of Goo and Gobbler production is the native unit of liquidity for a Uniswap V2 like automated market maker.

The rate of growth of Goo happened to be maximized when Goo = Mult. Thus, there was an evident comparison with Uniswap V2's $x * y = k$ constant product market maker design, where the point of maximization is also the point at which $X = Y$.

Thus, we built a special purpose AMM with vault-like characteristics and unique minting mechanics. What makes Goober different from Uniswap V2, aside from bonding an ERC20 with an ERC721, is the fact that the vault can mint new Gobblers when it's profitable to do so, returning them to the pool, increasing the rate of Goo emissions, and that it receives continuous Goo emissions, increasing Goo future emissions.

## Mechanism

### Overview

Utilizing an amalgamation of Uniswap V2's constant function market math, an ERC4626 yield-bearing vault (with GBR as the vault token), and automated VRGDA minting under certain market conditions, Goober aligns incentives to create an optimal balance of Goo and Gobbler multiplier for increased liquidity and Goo production across market conditions.

The rate of growth of Goo happened to be maximized when Goo = Mult. Thus, there was an evident comparison with Uniswap v2's $x * y = k$ constant product market maker design, where the point of maximization is also the point at which $X = Y$.

### Optimizing Goo production

Art Gobblers NFTs produce $Goo$ according to the formula:

$$\sqrt{Goo * Mult} = GooProduction$$

Where $Mult$ is the multiplier of Art Gobbler NFTs in a wallet and $Goo$ is the Goo balance of a wallet.

Goober implements a Uniswap V2 style $X*Y=K$ automated market maker where $X$ the total amount of $Goo$ in the vault, $Y$ is the vault's total Gobbler $Mult$, $K$ is the constant product of the reserves, $\sqrt{K}$ is the instantaneous $GooProduction$ at some time $t$, and GBR is the LP token.

The point of maximization for $\sqrt{Goo * Mult}$  happens to be at the point where  $Goo=Mult$. However, due to market forces, that may not always be the point with the highest yield in outside terms. Aligning the proportion of Goo and Gobblers in the vault with market forces using a bonding curve, optimizes for both Goo production and liquidity.

### GBR

GBR is the ERC4626-like ERC20 vault token herein referred to as $F$, representing fractions of the pool. The issuance and redemption rates of $F$ are determined by the change in $\sqrt{K}$, or $\Delta \sqrt{K}$, outlined in detail below.

#### Protocol Fees

The protocol charges a $2\%$ management in $F$ from what is minted during `deposit()` and $10\%$ on the growth of $\sqrt{K}$ in $F$ dilution. For example, if $\sqrt{K}$ grows by $10\%$, the protocol mints another $1\%$ of the total outstanding $F$ supply for itself.

The pool charges a 30 basis point swap fee, which accrues to GBR holders.


### Issuance

Since we want to optimize Goo emission, we create an incentive for increasing $\sqrt{K}$ upon `deposit()`.

The total rate of emission of the vault is tracked by a constant $\sqrt{K}$, where

$$
\sqrt{K} = \sqrt{Goo * Mult}
$$

When a deposit is made to the pool, a new $n$ value of reserves is calculated based on the amount of each asset added by depositor $d$,

$$
Goo_{n} = Goo_{i} + Goo_{d}
$$

and

$$
{ Mult }_{n} = { Mult }_{i} + Mult_{d}
$$

Now that we have some increase in our emission,

$$
{\sqrt{K}}_{n} > \sqrt{K}_{i}
$$

the depositor should be rewarded accordingly. Thus, the vault mints some amount of $F_{d}$, GBR to transfer to the depositor, where

$$
{ F }_{d}={ F }_{i} * \Delta \sqrt{K}
$$

or

$$
{ F }_{d}={ F }_{i} ( {\sqrt{K}_{n} - \sqrt{K}_{i} \over \sqrt{K}_{i}})
$$

subsituting for $K$, we get

$$
{ F }_{d}={ F }_{i} ( {\sqrt{(Goo_{n} * Mult_{n})} - \sqrt{(Goo_{i} * Mult_{i})} \over \sqrt{(Goo_{i} * Mult_{i})}})
$$

which can be simplified to

$$
{ F }_{d}={ F }_{i}  ({\sqrt{(Goo_{n} * Mult_{n})} \over \sqrt{(Goo_{i} * Mult_{i})}} -1)
$$

our issuance formula.

### Redemption

Since $\text {F}$ represents a fixed fraction of the pool. As the pool grows, so to will the assets redeemable by the fraction.

On withdraw, a user exchanges some $\text {F}$ for $Goo$ and/or $Mult$, burning the respective amount of $\text {F}$ in the process.

Since, a withdrawal decreases the reserves, then post withdraw:

$$ \sqrt{K}_{i} > \sqrt{K}_{n} $$

Since the pool's rate of $Goo$ emission has decreased, then so too must its supply of outstanding fractions by a proportionate amount.

We can derive the amount of reserves allotted to an amount of ${ F }_{d}$ from the inverse of the issuance calculation:

$$
{ F }_{d}={ F }_{i} ({\sqrt{(Goo_{w} * Mult_{w})} \over \sqrt{(Goo_{i} * Mult_{i})}} -1)
$$

which can be rearranged to

$$
{Goo_{w}} = {{(Goo_{i} * Mult_{i})}({{ F }_{d} \over { F }_{i}} + 1)^2 \over Mult_{w}}
$$

where $Goo_{w}$ and $Mult_{w}$ represent the respective amounts (each can be solved for interchangeably) that can be withdrawn simultaneously for some amount of fractions $F_{d}$ upon `withdraw()`.


### Liquid markets for Goo and Gobblers

Creating a liquid, balanced pool of Goo and Gobblers also enables users to swap efficiently between either asset, and for the vault to accrue fees and increase the growth of $K$ (Goo production).

For some `swap()` $s$ with initial reserves $Goo_{i}$ and $Mult_{i}$, the new balances $Goo_{n}$ and $Mult_{n}$ are determined by:

$$Goo_{n} = Goo_{i} + GooIn - GooOut$$

and

$$Mult_{n} = Mult_{i} + MultIn - MultOut$$

we can rewrite the net changes ($In - Out$) in Goo and Mult as $Goo_x$ and $Mult_x$ respectively.

#### Balancing the swap with erroneous Goo

Since we know the constant product $K$ must remain greater than or equal to the original $K$ after $s$, and because $Mult$ is not unitarily interchangable, if the inequality does not hold, there is some amount of `erroneousGoo` $Goo_e$, that must be added to $Goo_{x}$ as additional $GooIn$ or withdrawn from $Goo_{x}$ as additional $GooOut$ for $s$ to make the inequality hold such that:



$$\sqrt{K}_i \leq \sqrt{K}_n$$

thus,

$$ \sqrt{Goo_i * Mult_i} \leq \sqrt{Goo_n * Mult_n}$$

subsituting we get

$$ \sqrt{Goo_i * Mult_i} \leq \sqrt{(Goo_i + Goo_x) (Mult_i + Mult_x)}$$

or at point of equality:

$$ {Goo_i Mult_i} = {Goo_iMult_i+ Goo_xMult_i + Goo_iMult_x + Goo_xMult_x}$$

which we can rearrange to

$$ Mult_x = -{Goo_x(Mult_i + Mult_x)\over Goo_i}$$





or

$$ Goo_x = {-Goo_i \over (1 + {Mult_i \over Mult_x} )}$$

or

$$ Goo_x = -{Goo_iMult_x\over Mult_x + Mult_i}$$

therefore, the erroneous goo can be expressed as,

$$ Goo_e = {-Goo_i \over (1 +{Mult_i \over Mult_x})} - Goo_x$$

which can be used to balance a swap that doesn't have the correct parameters.

### Price impact

As with all constant function market makers, there will always be some price impact inherent to swaps, as a function of the size of the order in relation to the size of the pool. In the case of Goober, this is best expressed as a percentage change in the ratio between $Goo$ and $Mult$.

To solve for some price impact $I_s$ for `swap()` $s$, we must first calculate the change between the ratio of $Goo$ and $Mult$, the price impact for the swap expressed as an absolute change in the ratio of the reserves for $s$ is:

$$I_s = |\Delta{Goo \over Mult}|$$


or


$$I_s = |{{Goo_i \over Mult_i} - {Goo_n \over Mult_n}\over {Goo_i \over Mult_i}}|$$

which in the expanded form yields

$$I_s =  - {Mult_iGoo_n \over Goo_iMult_n}$$

and since we know that $Goo_n = Goo_i + Goo_x$, and $Mult_n = Mult_i + Mult_x$, then

$$I_s =  - {Mult_i(Goo_i + Goo_x) \over Goo_i(Mult_i +Mult_x)}$$



then we can subsitute $Mult_x$


$$I_s =  - {Mult_i(Goo_i -Goo_x) \over Goo_i(Mult_i -{Goo_x(Mult_i+Mult_x) \over Goo_i})}$$

or

$$I_s =  - {Mult_i(Goo_i -Goo_x) \over Mult_iGoo_i -Goo_x(Mult_i+Mult_x)}$$

or

$$I_s =  {Goo_x -Goo_i \over Goo_i -Goo_x+{Mult_x \over Mult_i}}$$

or

$$I_s =  {Goo_x -Goo_i \over Goo_i -Goo_x+\Delta Mult}$$

alternatively

$$I_s =  {Mult_i(Goo_x -Goo_i) \over Goo_iMult_i - Mult_iGoo_x +Mult_x }$$





which gives us the price impact $I_s$ in terms of values for $Goo_x$ and $Mult_x$ that maintain the exact constant product.

--------

### Flash swaps

Goober also allows for [flash swaps](https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/using-flash-swaps) which allow a user to receive and use some Goo or Gobblers before paying for them, as long as they make the repayment within the same atomic transaction.

The `swap()` function makes a call to an optional user-specified callback contract in between transferring out the tokens requested by the user and enforcing the invariant $K_i \leq K_n$ . Once the callback is complete, the contract checks the new balances and confirms that the invariant is satisfied, after adjusting for fees on the amounts paid in. If the contract does not have sufficient funds, it reverts the entire transaction. A user can also repay the Goober pool using the same token, rather than completing the `swap()`. This is effectively the same as letting anyone flash-borrow any of assets stored in a Goober pool, for the same dynamic fees as Goober charges for regular swaps.

### Minting

Since Goo growth of a given tank grows quadratically per added $Mult$, it is optimal for the growth of $K$ to increase $Mult$ as often as possible. On chain conditions determine when it is preferable for the pool, or an Externally Owned Account, to mint a new Gobbler from the VRGDA auction rather than buying a Gobbler at the pool's market rate.

#### Definitions

The weighted average multiplier of a newly minted Gobbler can be derived from the mint probabilities specified in the Art Gobblers smart contract, which yield an average $Mult$ per mint of

$$Mult_{avg}= 7.3294$$

Also we define,

$$ V = AuctionPrice$$

Where $AuctionPrice$ follows the [logistic VRGDA formula](https://www.paradigm.xyz/2022/08/vrgda#:~:text=Putting%20this%20all%20together%2C%20we%20end%20up%20with%20the%20following%20formula%3A) in $Goo$ based on the state-of-the-Art Gobblers smart contract at time $t_{i}$.

#### Discounting unrevealed Gobblers

At any time the Goober pool is willing to buy revealed Gobblers for a price $P_r$, which can be calculated as the absolute value of `gooErroneous` $Goo_e$ required to balance a one-sided swap of $Mult_{avg}$ for 0 $Goo$.

$$ P_r = |Goo_e| = {Goo_i \over (1 +{Mult_i \over Mult_{avg}})}$$



Given that price $P_r$ at which the pool is willing to buy a revealed Gobbler, there exists some price $P_u$ at which it is statistically profitable for the pool to buy an unrevealed Gobbler at some time $t_r$ away from reveal.

$P_u$ also happens to be the price it makes sense for the pool to pay for minting a new Gobbler from the VRGDA, which is functionally the same as buying an unrevealed Gobbler. Because of the Art Gobblers implementation, the value of $t_r$ can be found using modulo division on the present $t_{block}$ unix timestamp as follows

$$t_{day} = 86400$$

$$t_{reveal} = 40800$$

$$t_r = t_{block} \bmod t_{day} \bmod t_{reveal}$$

Emitted $Goo$ over some time $t$ is determined by the integral of the [instantaneous rate of goo growth](https://www.paradigm.xyz/2022/09/goo#:~:text=following%20differential%20equation%3A-,Solving%20it%20yields,-and%20expanding%2C%20we)

$$g(Goo, Mult, t) = {1 \over 4}(Mult * t)^2 + Goo + t \sqrt{Mult * Goo}$$

by calculating the pool's new reserves after buying an revealed Gobbler $Goo_n$

$$Goo_n = Goo_i - P_r$$

and the new $Mult$ after reveal, or if the pool had bought a similar revealed Gobbler

$$Mult_n = Mult_i + Mult_{avg}$$

since an unrevealed Gobbler has $Mult = 0$ until $t_r$, there will be a difference in emission $Goo_{r-i}$ between the reserves of the pool had it bought a revealed Gobbler for $P_r$ and had it bought an unrevealed Gobbler for $P_r$ at time $t_i$ over the time interval $t_r$ - $t_i$, which can be expressed as:


$$Goo_{r-i} = g(Goo_n, Mult_{n}, t_r) - g(Goo_n, Mult_i, t_r)$$

Therefore, we can express some discounted value of an unrevealed Gobbler in Goo at time $t_i$ as the extra reserves $Goo_x$ that must be present to satisfy $Goo_{r-1} = 0$

or

$$ g(Goo_n, Mult_{n}, t_r) = g(Goo_n + Goo_x, Mult_i, t_r) $$


or

$$ g(Goo_i - P_r, Mult_{i} + Mult_{avg}, t_r) = g(Goo_i-P_r + Goo_x, Mult_i, t_r) $$

simplifying, rearranging, substituting and solving for $Goo_x$, we get a [very long expression](https://www.wolframalpha.com/input?key=&i=1%2F4%28%28M%2BA%29t%29%5E2+%2B+t+*+sqrt%28%28M+%2B+A%29%28G+-%28G%2F%281+%2B+%28M%2FA%29%29%29%29%29+%3D+1%2F4%28M*t%29%5E2+%2B+X+%2B+t+*+sqrt%28M%28G-%28G%2F%281%2B%28M%2FA%29%29%29%2BX%29%29%2C+find+X). We can then subtract the discount $Goo_x$ from the known revealed Gobbler price $P_r$ to arrive at the price we can pay for an unrevealed Gobbler


$$P_u = P_r - Goo_x$$

therefore, an unrevealed Gobbler should be purchased from the VRGDA at time $t_i$ when

$$V \lt P_u$$

## Code

A experimental and permissively licensed (MIT) implementation of Goober can be found at [gooberxyz/goobervault](https://github.com/gooberxyz/goobervault). Pull requests with improvements are welcome.

## Conclusion

We believe Goober will democratize access to the Art Gobblers game, and make the GOO and VRGDA mechanics of the game function more smoothly over time.

If you are interested in integrating Goober into your project, we’d love to hear from you.

You can reach us on Twitter at [@mevbandit](https://twitter.com/mevbandit), [@0xAlcibiades](@0xAlcibiades), and [@CapitalGrug](https://twitter.com/CapitalGrug).