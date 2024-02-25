// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { EIP3009 } from "./EIP3009.sol";

contract MocaToken is EIP3009 {

    constructor(string memory name, string memory symbol, address treasury) ERC20(name, symbol) {

        _mint(treasury, 8_888_888_888);

    }


}


/**
name = Moca
symbol = MOCA
dp = 18

totalSupply = 8,888,888,888

 no burn function
 no mint function
 mint entire supply in constructor
 token contract should be renounced and non-upgradable

 */