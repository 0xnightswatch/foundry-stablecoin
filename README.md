# Stable Coin Project

## About the stable coin:
1. Pegged to the USD dollar 
    1. via a Chainlink pricefeed
    2. Set a function to exchange Eth and BTC
2. Stability mechanism: algorithmic (no centralized authority)
    1. Any one can mint the stable coin with enough collateral (coded)

3. Collateral type: Exogenous
    1. wETH
    2. wBTC

## Contract:

The protocol contain two main contracts: DecentralziedStableCoin and DSCEngine. 
DecentralziedStableCoin is reposible mainly for minting and burnig.
DSCEngine contains the major functions that as user interact with to deposit collateral, mint dsc, burn dsc, redeem collateral and liquidate other users.
DSCEngine own DecentrazliedStableCoin

## Libraries:
Mutiple libraries were used:
1. Chainlink brownie lib (imported)
    - may use other but it is small in size
2. openzeppelin lib (imported)
3. OracleLib 
    - created by me
    - this lib is used to make sure that the oracle is working and not stale
    - if it is stale or down, the contract will freeze.

## Scripts:
In script, we use two script. 
1. one script is used to deploy the contract
2. second script is used to get the network config for the contract and check if it going to work on:
    1. Sepolia 
    2. Local Anvil : it will deploy the essential mocks needed

## Test:
Test need more work
Not all the project is tested
I mainly focus on DSCEngine but I should test other contracts in the project

In DSCEngineTest.t.sol, there is a 

Fuzzing was used in testing
 - in foundry.toml, you can set fail_on_revert as true or false

## .env:
You need to creat a .env file or any type of file in order to provide the contract with a private key and --rpc-url

## Bug:
Liqudate Function:
- portocol require 200% colateralization
- liquadate function between 200 to 110%
- below 110%, there is a problem/bug. 


