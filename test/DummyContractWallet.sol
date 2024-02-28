// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract DummyContractWallet {

    // bytes4(keccak256("isValidSignature(bytes32,bytes)")
    bytes4 constant internal MAGICVALUE = 0x1626ba7e;
    address immutable public owner;
    
    constructor() {
        owner = msg.sender;
    }   

    // _hash: hash of the message being signed _> digest
    // _signature: bytes array containing the signature data -> signature
    // returns magic value if signer == owner
    function isValidSignature(bytes32 _hash, bytes memory _signature) public view returns (bytes4 magicValue) {

        address signer = recoverSigner(_hash, _signature);

        if (signer == address(0)) {
            return 0x00000000;
        } else if (signer == owner) {
            return MAGICVALUE;
        } else {
            return 0xffffffff;
        }
    }

    function recoverSigner(bytes32 messageHash, bytes memory signature) internal pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        if (signature.length != 65) {
            return address(0);
        }

        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        if (v < 27) {
            v += 27;
        }

        if (v != 27 && v != 28) {
            return address(0);
        }

        return ecrecover(messageHash, v, r, s);
    }


}
