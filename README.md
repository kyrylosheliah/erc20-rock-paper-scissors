# ERC20 implementation with Hardhat

## Overview

## Hardhat usage 

Compile the contract
```
npx hardhat compile
```

Run all the tests
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

## Foundry usage 

Initialize forge
```
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-contracts
forge install OpenZeppelin/openzeppelin-foundry-upgrades
forge install OpenZeppelin/openzeppelin-contracts-upgradeable
```

Run all the tests
```
forge test
```

Selectively run a test
```
forge test --match-test ContractTestName
forge test --match-path test-forge/ContractTestName.t.sol
```

### Foundry upgradeable deployment

Test the deployment
```
forge test -vvv --match-path test-forge/VTCTokenUpgradeableDeploy.t.sol
```

Deploy the contract on some net
```
forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY src/VTC/VTCTokenUpgradeable.sol:VTCTokenUpgradeable --broadcast
```
