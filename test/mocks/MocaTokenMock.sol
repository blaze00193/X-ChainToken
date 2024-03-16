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

    function deploymentChainId() public returns(uint256) {
        return _DEPLOYMENT_CHAINID;
    }
    
    function domainSeparator() public returns (bytes32) {
        return _domainSeparator();
    }

    function makeDomainSeperator(string memory name, string memory version, uint256 chainId) public returns (bytes32) {

        return
            keccak256(
                abi.encode(
                    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
                    0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                    keccak256(bytes(name)),
                    keccak256(bytes(version)),
                    chainId,
                    address(this)
                )
            );
    }
}
