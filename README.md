# Background

1. EIP2621 is broken: https://www.trust-security.xyz/post/permission-denied
2. We want to still offer gasless transaction for our users.
3. Solution: EIP3009

EIP3009 has been successfully used by Circle, in its USDC implementation since v1. This offers us a degree of confidence.

EIP3009.sol and its dependencies were taken from the repo linked below.

- They were initially built with solidity version 0.6; we have updated them to 0.8.
- As part of the update, the only refactoring done was changing `now` to `block.timestamp`.
- Additionally, EIP3009.sol now inherits ERC20.sol (from OpenZeppelin V5).
- EIP3009.sol used to inherit AbstractFiatTokenV2 - it no longer does.
- Reference to AbstractFiatTokenV2 and AbstractFiatTokenV1 were dropped.

src: https://etherscan.deth.net/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48#code

## Setup

- forge install
- npm install

