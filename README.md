# ERC20 implementation with Hardhat

## Overview

## Usage


Compile the contract
```
npx hardhat compile
```

To run all the tests

```
npx hardhat test
```

Selectively run the Solidity or `mocha` tests

```
npx hardhat test solidity
npx hardhat test mocha
```

Local chain deployment on http://127.0.0.1:8545/:
```
npx hardhat node
npx hardhat --network localhost ignition deploy ignition/modules/RockPaperScissors.ts
```
