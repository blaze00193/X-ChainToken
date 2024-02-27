// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {MocaToken} from "./../src/token/MocaToken.sol";

contract MocaTokenMock is MocaToken {

    constructor(string memory name, string memory symbol, address treasury) MocaToken(name, symbol, treasury) {

    }   


    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }

}
