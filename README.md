# generalized-lending-protocol

A simple, modern, optimized lending protocol. Note that this codebase has not been audited and should therefore only be used an example/reference for other developers. 

## Overview

The lending contracts contained in this repository aim to resemble a fully open lending protocol, enabling anyone to create their own isolated lending markets, similar to Euler.xyz and Fuse by Rari Capital. 

In order to do this, the protocol consists of two main contracts: the `LendingPoolFactory` and `LendingPool`. The `LendingPoolFactory` can be utilized by pool creators to deploy individual `LendingPool` contracts. Each one of these contracts form their own, isolated lending markets, enabling users to lend and borrow different assets. 

## Architecture

Although most lending protocols are designed to support tokenized deposits by having seperate ERC20 contracts for each asset, this lending protocol uses a single contract to represent each lending market. This 1) makes the protocol far more efficient by heavily decreasing the number of cross-contract calls, and 2) makes it much easier for other protocols and developers to integrate with.

While balances can no longer be fungible with this model, ERC20 and ERC1155 wrappers can easily be developed to enable tokenized deposits. 

Another interesting feature built into the lending protocol is the storage of funds in ERC4626 vaults. Rather than holding the tokens within the `LendingPool` contract, they are transfered to an ERC4626 vault specified by the pool creator. This enables idle assets to be put to use in a variety of different ways (e.g. earning interest, metagovernance (token delegation), etc).

<p align="center">
  <img src="https://i.imgur.com/EfGL9MA.png" width="400px" />
</p>

## Setup

This repository uses Foundry for compilation and testing. To build and test the contracts, you can run the following

```sh
forge build #compile
forge test  # test
```

### Credits

I'd like to thank [Jack Longarzo](https://github.com/JLongarzo), [Pedro Maia](https://github.com/pedrommaiaa), [Jai Bhavnani](https://github.com/JBhav24), [Joey Santoro](https://github.com/Joeysantoro), and [t11s](https://github.com/transmissions11) for their support on this project.