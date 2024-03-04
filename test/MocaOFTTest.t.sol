// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";

import {MocaOFTMock} from "./mocks/MocaOFTMock.sol";
import {DummyContractWallet} from "./mocks/DummyContractWallet.sol";
import {EndpointV2Mock} from "./mocks/EndpointV2Mock.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// SendParam
import "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Origin } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";


abstract contract StateDeployed is Test {
    
    MocaOFTMock public mocaToken;
    DummyContractWallet public dummyContract;
    EndpointV2Mock public lzMock;

    address public deployer;
    address public treasury;
    address public userA;
    address public relayer;
    uint256 public deployerPrivateKey;
    
    address public delegate;
    address public owner;

    function setUp() public {

        //users
        treasury = makeAddr('treasury');
        userA = makeAddr('userA');
        relayer = makeAddr('relayer');
        delegate = makeAddr('delegate');
        owner = makeAddr('owner');

        deployerPrivateKey = 0xDEEEE;
        deployer = vm.addr(deployerPrivateKey);

        vm.startPrank(deployer);

        // contracts
        string memory name = "TestToken"; 
        string memory symbol = "TT";
        
        lzMock = new EndpointV2Mock();
        mocaToken = new MocaOFTMock(name, symbol, address(lzMock), deployer, deployer);
        dummyContract = new DummyContractWallet();

        vm.stopPrank();
    }

    function _getTransferHash(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce) public view returns (bytes32){
        
        // from _transferWithAuthorization()
        bytes memory typeHashAndData = abi.encode(
            mocaToken.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
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

    function _getCancelHash(address authorizer, bytes32 nonce) public view returns (bytes32) {

        // from _cancelAuthorization()
        bytes memory typeHashAndData = abi.encode(
            mocaToken.CANCEL_AUTHORIZATION_TYPEHASH(),
            authorizer,
            nonce
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", mocaToken.DOMAIN_SEPARATOR(), keccak256(typeHashAndData)));

        return digest;
    }

    function _getReceiveHash(address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce) public view returns (bytes32) {

        // from _cancelAuthorization()
        bytes memory typeHashAndData = abi.encode(
            mocaToken.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", mocaToken.DOMAIN_SEPARATOR(), keccak256(typeHashAndData)));

        return digest;
    }

}

//Note: EOA signatures
contract StateDeployedTest is StateDeployed {

    function testTotalSupply() public {
        
        // check minted supply
        assertEq(mocaToken.totalSupply(), 0);
        assertEq(mocaToken.balanceOf(treasury), 0);
        assertEq(mocaToken.balanceOf(deployer), 0);
    }

    function testTransferWithAuthorization() public {

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

        // check that nonce is false
        bool isFalse = mocaToken.authorizationState(from, nonce);
        assertEq(isFalse, false);

        // verify
        mocaToken.transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);

        // check balances
        assertEq(mocaToken.balanceOf(from), 0);
        assertEq(mocaToken.balanceOf(to), value);
        

        // check that nonce is true
        bool isTrue = mocaToken.authorizationState(from, nonce);
        assertEq(isTrue, true);


        // check that signature cannot be replayed
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);

        // check that signature cannot be replayed on another fn call
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.cancelAuthorization(from, nonce, v, r, s);

        // check that signature cannot be replayed on another fn call
        vm.prank(to);
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);
    }

    function testCancelAuthorization() public {

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
        bytes32 digest = _getCancelHash(from, nonce);

        // sign 
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderPrivateKey, digest);

        // check that nonce is false
        bool isFalse = mocaToken.authorizationState(from, nonce);
        assertEq(isFalse, false);

        // 
        vm.warp(5);
        vm.prank(relayer);
        mocaToken.cancelAuthorization(from, nonce, v, r, s);

        // check that nonce is true
        bool isTrue = mocaToken.authorizationState(from, nonce);
        assertEq(isTrue, true);

        // check that signature cannot be replayed
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.cancelAuthorization(from, nonce, v, r, s);

        // check that signature cannot be replayed on another fn call
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);

        // check that signature cannot be replayed on another fn call
        vm.prank(to);
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);
    }

    function testReceiveWithAuthorization() public {
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
        bytes32 digest = _getReceiveHash(from, to, value, validAfter, validBefore, nonce);

        // sign 
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderPrivateKey, digest);

        // check that nonce is false
        bool isFalse = mocaToken.authorizationState(from, nonce);
        assertEq(isFalse, false);

        // execute gasless transfer. caller MUST be the payee. 
        vm.warp(5);
        vm.prank(to);
        mocaToken.receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);

        // check balances
        assertEq(mocaToken.balanceOf(from), 0);
        assertEq(mocaToken.balanceOf(to), value);
        

        // check that nonce is true
        bool isTrue = mocaToken.authorizationState(from, nonce);
        assertEq(isTrue, true);

        // check that signature cannot be replayed
        vm.prank(to);
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);

        // check that signature cannot be replayed on another fn call
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);
        // check that signature cannot be replayed on another fn call
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.cancelAuthorization(from, nonce, v, r, s);
    }

    function testInvalidCallerReceiveWithAuthorization() public {
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
        bytes32 digest = _getReceiveHash(from, to, value, validAfter, validBefore, nonce);

        // sign 
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderPrivateKey, digest);

        // check that nonce is false
        bool isFalse = mocaToken.authorizationState(from, nonce);
        assertEq(isFalse, false);

        vm.warp(5);
        
        // execute gasless transfer. caller IS NOT payee. THIS SHOULD REVERT.
        
        vm.prank(treasury);
        vm.expectRevert("Caller must be the payee");
        mocaToken.receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);
    }
}

//Note: SmartContract signatures 
contract StateDeployedTest1271 is StateDeployed {

    function testTransferWithAuthorization() public {

        // mint to sender: sender is dummy contract
        address sender = address(dummyContract);
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

        // sign as deployer == owner
        assertEq(dummyContract.owner(), deployer);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, digest);

        // execute gasless transfer. signature relayed by 3rd party
        vm.warp(5);

        // check that nonce is false
        bool isFalse = mocaToken.authorizationState(from, nonce);
        assertEq(isFalse, false);

        // verify
        mocaToken.transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);

        // check balances
        assertEq(mocaToken.balanceOf(from), 0);
        assertEq(mocaToken.balanceOf(to), value);
        

        // check that nonce is true
        bool isTrue = mocaToken.authorizationState(from, nonce);
        assertEq(isTrue, true);


        // check that signature cannot be replayed
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);

        // check that signature cannot be replayed on another fn call
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.cancelAuthorization(from, nonce, v, r, s);
        // check that signature cannot be replayed on another fn call
        vm.prank(to);
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);

    }

    function testCancelAuthorization() public {

        // mint to sender: sender is dummy contract
        address sender = address(dummyContract);
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
        bytes32 digest = _getCancelHash(from, nonce);

        // sign 
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, digest);

        // check that nonce is false
        bool isFalse = mocaToken.authorizationState(from, nonce);
        assertEq(isFalse, false);

        // 
        vm.warp(5);
        vm.prank(relayer);
        mocaToken.cancelAuthorization(from, nonce, v, r, s);

        // check that nonce is true
        bool isTrue = mocaToken.authorizationState(from, nonce);
        assertEq(isTrue, true);

        // check that signature cannot be replayed
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.cancelAuthorization(from, nonce, v, r, s);

        // check that signature cannot be replayed on another fn call
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);
        // check that signature cannot be replayed on another fn call
        vm.prank(to);
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);

    }

    function testReceiveWithAuthorization() public {

        // mint to sender: sender is dummy contract
        address sender = address(dummyContract);
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
        bytes32 digest = _getReceiveHash(from, to, value, validAfter, validBefore, nonce);

        // sign 
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, digest);

        // check that nonce is false
        bool isFalse = mocaToken.authorizationState(from, nonce);
        assertEq(isFalse, false);

        // execute gasless transfer. caller MUST be the payee. 
        vm.warp(5);
        vm.prank(to);
        mocaToken.receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);

        // check balances
        assertEq(mocaToken.balanceOf(from), 0);
        assertEq(mocaToken.balanceOf(to), value);
        

        // check that nonce is true
        bool isTrue = mocaToken.authorizationState(from, nonce);
        assertEq(isTrue, true);

        // check that signature cannot be replayed
        vm.prank(sender);
        vm.expectRevert("Caller must be the payee");
        mocaToken.receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);

        // check that signature cannot be replayed on another fn call
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);
        // check that signature cannot be replayed on another fn call
        vm.expectRevert("Authorization is used or canceled");
        mocaToken.cancelAuthorization(from, nonce, v, r, s);
    }
    

    function testInvalidCallerReceiveWithAuthorization() public {

        // mint to sender: sender is dummy contract
        address sender = address(dummyContract);
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
        bytes32 digest = _getReceiveHash(from, to, value, validAfter, validBefore, nonce);

        // sign 
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, digest);

        // check that nonce is false
        bool isFalse = mocaToken.authorizationState(from, nonce);
        assertEq(isFalse, false);

        vm.warp(5);
        
        // execute gasless transfer. caller IS NOT payee. THIS SHOULD REVERT.
        
        vm.prank(treasury);
        vm.expectRevert("Caller must be the payee");
        mocaToken.receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);
    } 

}


contract StateDeployedTestPausable is StateDeployed {

    function testUserCannotCallPause() public {
        
        assertEq(mocaToken.paused(), false);
        
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userA));
        mocaToken.pause();

        assertEq(mocaToken.paused(), false);
    }

    function testOwnerCanCallPause() public {
        
        assertEq(mocaToken.paused(), false);

        vm.prank(deployer);
        mocaToken.pause();

        assertEq(mocaToken.paused(), true);

        vm.prank(deployer);
        mocaToken.unpause();

        assertEq(mocaToken.paused(), false);
    }

    function testPausedSend() public {

        vm.prank(deployer);
        mocaToken.pause();


        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: 1111,
            to: bytes32(uint256(uint160(address(deployer)))),
            amountLD: 1 ether,
            minAmountLD: 1 ether,
            extraOptions: nullBytes,
            composeMsg: nullBytes,
            oftCmd: nullBytes
        });

        MessagingFee memory messagingFee;
        messagingFee.lzTokenFee = 0;
        messagingFee.nativeFee = 0;

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        mocaToken.send{value: messagingFee.nativeFee}(sendParam, messagingFee, payable(deployer));
    }

    function testPauseLzReceive() public {
        vm.prank(deployer);
        mocaToken.pause();


        Origin memory _origin;
        bytes32 _guid;
        bytes memory _message;
        address unnamedAddress;  
        bytes memory unnamedBytes;

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        mocaToken.mockLzReceive(_origin, _guid, _message, unnamedAddress, unnamedBytes);
    }

    function testTransferPaused() public {
        vm.prank(deployer);
        mocaToken.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        mocaToken.transfer(userA, 1 ether);

    }

    function testTransferFromPaused() public {
        vm.prank(deployer);
        mocaToken.pause();
        
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        mocaToken.transferFrom(deployer, userA, 1 ether);

    }

    function testApprovePaused() public {
        vm.prank(deployer);
        mocaToken.pause();
        
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        mocaToken.approve(userA, 1 ether);
    }

}