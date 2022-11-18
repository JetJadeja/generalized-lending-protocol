# fuse-v2 (WIP)

Smart contracts for the second iteration of Fuse by Rari Capital.

## Setup

Fuse uses Foundry for compilation and testing. To install foundry, simply run:

```
cargo install --git https://github.com/gakonst/foundry --bin forge --locked
```

Next, to install all dependencies and setup the project, run:

```
make
```

To test the contracts, just run `forge test`. If you simply want to compile them, run `forge build`.

## Architecture

Unlike the Compound design, Fuse v2 does not employ the cToken model, in which each market is represented by separate contracts connected to each other through a Comptroller contract.

Instead, Fuse v2 adopts the architecture depicted below, where each pool is represented by a single FusePool contract. This new architecture causes decreased deployment and execution costs, as all logic is stored and executed in a single contract, decreasing the amount of the cross-contract calls.

While balances can no longer be fungible on the base layer because all markets are represented by a single contract, ERC20 and ERC1155 wrappers can be easily developed.

Instead of being stored within the FusePool contract, the funds will be held in various ERC4626 Vaults, enabling interest on idle funds, metagovernance, and so on...

<p align="center">
  <img src="https://i.imgur.com/FugCHSU.png" width="400px" />
</p>
