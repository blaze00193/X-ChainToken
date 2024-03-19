// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "forge-std/Test.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";              

import {MocaOFTMock, MocaOFT} from "./mocks/MocaOFTMock.sol";
import {DummyContractWallet} from "./mocks/DummyContractWallet.sol";
import {EndpointV2Mock} from "./mocks/EndpointV2Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// SendParam
import "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Origin } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";


abstract contract StateDeployed is Test {

    MocaOFTMock public mocaToken;
    DummyContractWallet public dummyContract;
    EndpointV2Mock public lzMock;

    address public deployer;
    uint256 public deployerPrivateKey;

    address public treasury;
    address public userA;
    address public operator;
    address public relayer;

    event PeerSet(uint32 eid, bytes32 peer);
    event SetWhitelist(address indexed addr, bool isWhitelist);

    function setUp() virtual public {

        //users
        treasury = makeAddr('treasury');
        userA = makeAddr('userA');
        operator = makeAddr('operator');
        relayer = makeAddr('relayer');


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

    function testDeploymentChainId() public {
        uint256 _DEPLOYMENT_CHAINID = mocaToken.deploymentChainId();
        assertTrue(_DEPLOYMENT_CHAINID == block.chainid);
    }

    function testDomainSeparator() public {
        string memory name = "TestToken"; 
        string memory symbol = "TT";
        
        bytes32 domainSeparator = mocaToken.makeDomainSeperator(name, "v1", block.chainid);
        assertTrue(domainSeparator == mocaToken.domainSeparator());
    }

    function testCannotTransferWithInvalidSignature() public {

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

        // will revert on invalid signature
        vm.expectRevert("Invalid signature");
        mocaToken.transferWithAuthorization(from, to, 10 ether, validAfter, validBefore, nonce, v, r, s);

    }

    function testCannotTransferIfAfterThanValidBefore() public {

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
        vm.warp(validBefore + 10);
        vm.prank(relayer);

        // check that nonce is false
        bool isFalse = mocaToken.authorizationState(from, nonce);
        assertEq(isFalse, false);

        // will revert on invalid signature
        vm.expectRevert("Authorization is expired");
        mocaToken.transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);

    }

    function testCannotTransferIfBeforeThanValidAfter() public {

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
        vm.warp(validAfter - 1);
        vm.prank(relayer);

        // check that nonce is false
        bool isFalse = mocaToken.authorizationState(from, nonce);
        assertEq(isFalse, false);

        // will revert on invalid signature
        vm.expectRevert("Authorization is not yet valid");
        mocaToken.transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);

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

abstract contract StateRateLimits is StateDeployed {
    
    uint32 public eid = 1;
    bytes32 public peer = bytes32(uint256(uint160(makeAddr('somePeer'))));  

    function setUp() virtual override public {
        super.setUp();

        vm.startPrank(deployer);

        mocaToken.setPeer(eid, peer);
        
        mocaToken.setOutboundLimit(eid, 5 ether);
        mocaToken.setInboundLimit(eid, 5 ether);
        mocaToken.setOperator(operator, true);
    
        vm.stopPrank();
        
        vm.prank(userA);
        mocaToken.mint(10 ether);
        // gas
        vm.deal(userA, 10 ether);

    }
}

contract StateRateLimitsTest is StateRateLimits {

    function testCannotExceedGlobalSupply() public {
        vm.startPrank(userA);
        mocaToken.mint(8_888_888_888 ether);

        vm.expectRevert(abi.encodeWithSelector(MocaOFT.ExceedGlobalSupply.selector, (8_888_888_888 ether + 10 ether), 9_888_888_888 ether));
        mocaToken.credit(userA, 9_888_888_888 ether, eid);

        vm.stopPrank();
    }
    
    function testCannotExceedInboundLimits() public {
        
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(MocaOFT.ExceedInboundLimit.selector, 5 ether, 10 ether));
        
        mocaToken.credit(userA, 10 ether, eid);
    }

    function testCannotExceedOutboundLimits() public {

        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: 1,                                                               // Destination endpoint ID.
            to: bytes32(uint256(uint160(userA))),  // Recipient address.
            amountLD: 10 ether,                                                                  // Amount to send in local decimals        
            minAmountLD: 10 ether,                                                               // Minimum amount to send in local decimals.
            extraOptions: nullBytes,                                                             // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: nullBytes,                                                               // The composed message for the send() operation.
            oftCmd: nullBytes                                                                    // The OFT command to be executed, unused in default OFT implementations.
        });

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(MocaOFT.ExceedOutboundLimit.selector, 5 ether, 10 ether));
        mocaToken.send(sendParam, MessagingFee({nativeFee: 1 ether, lzTokenFee: 0}), userA);
    }


    function testInboundLimitsWithinPeriod() public {
        
        uint256 initialReceiveTokenAmount = mocaToken.receivedTokenAmounts(eid);
        uint256 initialReceiveTimestamp = mocaToken.lastReceivedTimestamps(eid);
        assertTrue(initialReceiveTimestamp == 0);        
        assertTrue(initialReceiveTokenAmount == 0);  

        vm.warp(5);

        vm.prank(userA);        
        uint256 amountReceived = mocaToken.credit(userA, 5 ether, eid);
        assertTrue(amountReceived == 0 ether);

        // reflects minting of new tokens
        assertTrue(mocaToken.balanceOf(userA) == 15 ether);
        
        // check timestamp and cumulative received amount UNCHANGED. 
        assertTrue(mocaToken.receivedTokenAmounts(eid) == initialReceiveTokenAmount + 5 ether);
        assertTrue(mocaToken.lastReceivedTimestamps(eid) == initialReceiveTimestamp);     
    }

    function testInboundLimitsBeyondPeriod() public {
        
        uint256 initialReceiveTokenAmount = mocaToken.receivedTokenAmounts(eid);
        uint256 initialReceiveTimestamp = mocaToken.lastReceivedTimestamps(eid);
        assertTrue(initialReceiveTimestamp == 0);        
        assertTrue(initialReceiveTokenAmount == 0);        

        vm.warp(86400);

        assertTrue(block.timestamp > initialReceiveTimestamp);


        vm.prank(userA);        
        uint256 amountReceived = mocaToken.credit(userA, 5 ether, eid);
        assertTrue(amountReceived == 0 ether);

        // reflects minting of new tokens
        assertTrue(mocaToken.balanceOf(userA) == 15 ether);
        
        assertTrue(mocaToken.receivedTokenAmounts(eid) == initialReceiveTokenAmount + 5 ether);
        assertTrue(mocaToken.lastReceivedTimestamps(eid) == 86400);     
    }

    function testOutboundLimitsWithinPeriod() public {
        
        uint256 initialSentTokenAmount = mocaToken.sentTokenAmounts(eid);
        uint256 initialSentTimestamp = mocaToken.lastSentTimestamps(eid);
        assertTrue(initialSentTimestamp == 0);        
        assertTrue(initialSentTokenAmount == 0); 

        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: eid,                                                                        // Destination endpoint ID.
            to: peer,                                                                             // Recipient address.
            amountLD: 5 ether,                                                                   // Amount to send in local decimals        
            minAmountLD: 5 ether,                                                                // Minimum amount to send in local decimals.
            extraOptions: nullBytes,                                                             // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: nullBytes,                                                                // The composed message for the send() operation.
            oftCmd: nullBytes                                                                    // The OFT command to be executed, unused in default OFT implementations.
        });

        vm.warp(5);

        vm.prank(userA);
        mocaToken.send(sendParam, MessagingFee({nativeFee: 0 ether, lzTokenFee: 0}), payable(userA));

        assertTrue(mocaToken.balanceOf(userA) == 5 ether);

        // check timestamp and cumulative received amount UNCHANGED. 
        assertTrue(mocaToken.sentTokenAmounts(eid) == initialSentTokenAmount + 5 ether);
        assertTrue(mocaToken.lastSentTimestamps(eid) == initialSentTimestamp); 
    }

    function testOutboundLimitsBeyondPeriod() public {
        
        uint256 initialSentTokenAmount = mocaToken.sentTokenAmounts(eid);
        uint256 initialSentTimestamp = mocaToken.lastSentTimestamps(eid);
        assertTrue(initialSentTimestamp == 0);        
        assertTrue(initialSentTokenAmount == 0);        

        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: eid,                                                                        // Destination endpoint ID.
            to: peer,                                                                             // Recipient address.
            amountLD: 5 ether,                                                                   // Amount to send in local decimals        
            minAmountLD: 5 ether,                                                                // Minimum amount to send in local decimals.
            extraOptions: nullBytes,                                                             // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: nullBytes,                                                                // The composed message for the send() operation.
            oftCmd: nullBytes                                                                    // The OFT command to be executed, unused in default OFT implementations.
        });

        vm.warp(86400);

        vm.prank(userA);
        mocaToken.send(sendParam, MessagingFee({nativeFee: 0 ether, lzTokenFee: 0}), payable(userA));

        assertTrue(mocaToken.balanceOf(userA) == 5 ether);

        // check timestamp and cumulative received amount UNCHANGED. 
        assertTrue(mocaToken.sentTokenAmounts(eid) == initialSentTokenAmount + 5 ether);
        assertTrue(mocaToken.lastSentTimestamps(eid) == 86400);     
    }


    function testWhitelistInbound() public {
        
        vm.expectEmit(false, false, false, false);
        emit SetWhitelist(userA, true);

        vm.prank(deployer);
        mocaToken.setWhitelist(userA, true);

        uint256 initialReceiveTokenAmount = mocaToken.receivedTokenAmounts(eid);
        uint256 initialReceiveTimestamp = mocaToken.lastReceivedTimestamps(eid);
                
        vm.prank(userA);        
        uint256 amountReceived = mocaToken.credit(userA, 10 ether, eid);

        // NOTE: Returns 0 in foundry tests.
        //       returns the correct amount of tokens when checking testnet deployment
        //       testnet event emission was observed to reflect the correct token value.
        //       see: https://mumbai.polygonscan.com/address/0x8c979ef6a647c91f56654580f1c740c9f047edb2#events
        assertTrue(amountReceived == 0 ether);
        
        // reflects minting of new tokens
        assertTrue(mocaToken.balanceOf(userA) == 20 ether);
        
        // check timestamp and cumulative received amount UNCHANGED. 
        assertTrue(mocaToken.receivedTokenAmounts(eid) == initialReceiveTokenAmount);
        assertTrue(mocaToken.lastReceivedTimestamps(eid) == initialReceiveTimestamp);
    }

    function testWhitelistOutbound() public {
        vm.prank(deployer);
        mocaToken.setWhitelist(userA, true);

        uint256 initialSentTokenAmount = mocaToken.sentTokenAmounts(eid);
        uint256 initialSentTimestamp = mocaToken.lastSentTimestamps(eid);

        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: eid,                                                                        // Destination endpoint ID.
            to: peer,                                                                             // Recipient address.
            amountLD: 10 ether,                                                                   // Amount to send in local decimals        
            minAmountLD: 10 ether,                                                                // Minimum amount to send in local decimals.
            extraOptions: nullBytes,                                                             // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: nullBytes,                                                                // The composed message for the send() operation.
            oftCmd: nullBytes                                                                    // The OFT command to be executed, unused in default OFT implementations.
        });

        vm.prank(userA);
        mocaToken.send(sendParam, MessagingFee({nativeFee: 0 ether, lzTokenFee: 0}), payable(userA));

        // 0, since they were "sent" and therefore burnt/locked
        assertTrue(mocaToken.balanceOf(userA) == 0);

        // check timestamp and cumulative received amount UNCHANGED. 
        assertTrue(mocaToken.sentTokenAmounts(eid) == initialSentTokenAmount);
        assertTrue(mocaToken.lastSentTimestamps(eid) == initialSentTimestamp);
    }

    function testUserCannotResetPeer() public {
        
        vm.prank(userA);
        vm.expectRevert("Not Operator");
        mocaToken.resetPeer(eid);
    }

    function testOperatorCanResetPeers() public {
        
        vm.expectEmit(false, false, false, false);
        emit PeerSet(eid, bytes32(0));
        
        vm.prank(operator);
        mocaToken.resetPeer(eid);
        
        assertTrue(mocaToken.peers(eid) == bytes32(0));
    }

}

abstract contract StateRateReset is StateRateLimits {

    function setUp() virtual override public {
        super.setUp();

        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: eid,                                                                        // Destination endpoint ID.
            to: peer,                                                                             // Recipient address.
            amountLD: 5 ether,                                                                   // Amount to send in local decimals        
            minAmountLD: 5 ether,                                                                // Minimum amount to send in local decimals.
            extraOptions: nullBytes,                                                             // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: nullBytes,                                                                // The composed message for the send() operation.
            oftCmd: nullBytes                                                                    // The OFT command to be executed, unused in default OFT implementations.
        });


        vm.startPrank(userA);

        uint256 amountReceived = mocaToken.credit(userA, 5 ether, 1);
        mocaToken.send(sendParam, MessagingFee({nativeFee: 0 ether, lzTokenFee: 0}), payable(userA));

        vm.stopPrank();

        assertTrue(mocaToken.receivedTokenAmounts(eid) == 5 ether);
        assertTrue(mocaToken.sentTokenAmounts(eid) == 5 ether);
    }
}

contract StateRateRestTest is StateRateReset {

    function testUserCannotResetReceivedTokenAmount() public {

        assertTrue(mocaToken.receivedTokenAmounts(eid) == 5 ether);

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userA));
        mocaToken.resetReceivedTokenAmount(1);

        assertTrue(mocaToken.receivedTokenAmounts(eid) == 5 ether);
    }

    function testOwnerCanResetReceivedTokenAmount() public {
        assertTrue(mocaToken.receivedTokenAmounts(eid) == 5 ether);

        vm.prank(deployer);
        mocaToken.resetReceivedTokenAmount(eid);

        assertTrue(mocaToken.receivedTokenAmounts(eid) == 0);
    }

    function testUserCannotResetSentTokenAmount() public {
        assertTrue(mocaToken.sentTokenAmounts(eid) == 5 ether);
       
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userA));
        mocaToken.resetSentTokenAmount(eid);

        assertTrue(mocaToken.sentTokenAmounts(eid) == 5 ether);
    }

    function testOwnerCanResetSentTokenAmount() public {
        assertTrue(mocaToken.sentTokenAmounts(eid) == 5 ether);

        vm.prank(deployer);
        mocaToken.resetSentTokenAmount(eid);

        assertTrue(mocaToken.sentTokenAmounts(eid) == 0);
    }

} 