// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";

//import {MocaToken} from "./../src/token/MocaToken.sol";
import {MocaOFT} from "./../src/token/MocaOFT.sol";
import {MocaTokenAdaptor} from "./../src/token/MocaTokenAdaptor.sol";

import {MocaTokenMock} from "./MocaTokenMock.sol";

abstract contract StateDeployed is Test {
    
    MocaTokenMock public mocaToken;

    address public deployer;
    address public treasury;
    address public userA;
    address public relayer;

    function setUp() public {

        //users
        deployer = makeAddr('deployer');
        treasury = makeAddr('treasury');
        userA = makeAddr('userA');
        relayer = makeAddr('relayer');

        vm.prank(deployer);

        // contracts
        string memory name = "TestToken"; 
        string memory symbol = "TT";
        
        mocaToken = new MocaTokenMock(name, symbol, treasury);

    }
}


contract StateDeployedTest is StateDeployed {

    function testTotalSupply() public {
        
        // check minted supply
        assertEq(mocaToken.totalSupply(), 8_888_888_888 * 1e18);
        assertEq(mocaToken.balanceOf(treasury), 8_888_888_888 * 1e18);
        assertEq(mocaToken.balanceOf(deployer), 0);

    }

    function testValidSignature() public {
        
/*
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPrivateKey, 
            keccak256(abi.encodePacked("\x19\x01", mocaToken.DOMAIN_SEPARATOR(), question4.sellOrderDigest(sellOrder)))
        );
*/

        // create sender
        uint256 senderPrivateKey = 0xA11CE;
        address sender = vm.addr(senderPrivateKey);
        
        // mint to sender
        vm.prank(sender);
        mocaToken.mint(1 ether);

        // SigParams
        address from = sender;
        address to = userA;
        uint256 value = 1 ether;
        uint256 validAfter = 1; 
        uint256 validBefore = block.timestamp + 1000;
        bytes32 nonce = hex"00";

        // prepare transferHash
        bytes32 digest = _getTransferHash(from, to, value, validAfter, validBefore, nonce);

        // sign 
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderPrivateKey, digest);

        // execute gasless transfer. signature relayed by 3rd party
        vm.warp(5);
        vm.prank(relayer);
        mocaToken.transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);


    }


    function _getTransferHash(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce) private view returns (bytes32){
        
        // from _transferWithAuthorization()
        bytes memory typeHashAndData = abi.encode(
            mocaToken.TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce
        );

        // from EIP712.recover()
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", mocaToken.DOMAIN_SEPARATOR(), keccak256(typeHashAndData)));

        return digest;
    }
}
