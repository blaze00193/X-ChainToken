// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {MocaToken} from "./../../src/MocaToken.sol";

contract MocaTokenMock is MocaToken {

    // bytes4(keccak256("isValidSignature(bytes32,bytes)")
    bytes4 constant internal MAGICVALUE = 0x1626ba7e;
    address immutable public owner;
    
    constructor(string memory name, string memory symbol, address treasury) MocaToken(name, symbol, treasury) {
        owner = msg.sender;
    }   


    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }

}
