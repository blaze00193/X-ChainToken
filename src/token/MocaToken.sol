// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { EIP3009 } from "./EIP3009.sol";

contract MocaToken is EIP3009, Ownable {

    constructor(string memory name, string memory symbol, address owner) ERC20(name, symbol) Ownable(owner) {}


    // free mint baby
    function mint(uint256 amount) external {

        _mint(msg.sender, amount);
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