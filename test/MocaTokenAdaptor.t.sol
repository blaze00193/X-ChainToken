// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";

import "test/mocks/MockTokenAdaptor.sol";
//import { MocaOFTMock } from "./mocks/MocaOFTMock.sol";
import { MocaTokenMock } from "./mocks/MocaTokenMock.sol";
import { EndpointV2Mock } from "./mocks/EndpointV2Mock.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";


// SendParam
import "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Origin } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";


abstract contract StateDeployed is Test {
    
    MockTokenAdapter public mocaTokenAdapter;
    EndpointV2Mock public lzMock;
    MocaTokenMock public mocaToken;

    address public deployer;
    uint256 public deployerPrivateKey;
    
    address public userA;
    address public delegate;
    address public operator;
    address public relayer;
    address public treasury;

    event PeerSet(uint32 eid, bytes32 peer);
    event SetWhitelist(address indexed addr, bool isWhitelist);
    
    function setUp() virtual public {

        //users
        userA = makeAddr('userA');
        delegate = makeAddr('delegate');
        operator = makeAddr('operator');
        relayer = makeAddr('relayer');
        treasury = makeAddr('treasury');

        deployerPrivateKey = 0xDEEEE;
        deployer = vm.addr(deployerPrivateKey);

        vm.startPrank(deployer);

        // contracts
        string memory name = "TestToken"; 
        string memory symbol = "TT";
        
        lzMock = new EndpointV2Mock();
        mocaToken = new MocaTokenMock(name, symbol, treasury);
        mocaTokenAdapter = new MockTokenAdapter(address(mocaToken), address(lzMock), delegate, deployer);

        vm.stopPrank();
    }
}

abstract contract StateRateLimits is StateDeployed {
    
    uint32 public srcid = 1;
    uint32 public dstid = 1;
    bytes32 public peer = bytes32(uint256(uint160(treasury)));  

    function setUp() virtual override public {
        super.setUp();

        vm.startPrank(deployer);

        dstid = 1;
        peer = bytes32(uint256(uint160(treasury)));  
        mocaTokenAdapter.setPeer(dstid, peer);
        
        mocaTokenAdapter.setOutboundLimit(1, 5 ether);
        mocaTokenAdapter.setInboundLimit(1, 5 ether);
        mocaTokenAdapter.setOperator(operator, true);
    
        vm.stopPrank();
        
        vm.startPrank(userA);
            mocaToken.mint(10 ether);
            mocaToken.approve(address(mocaTokenAdapter), 10 ether);
        vm.stopPrank();

        vm.prank(address(mocaTokenAdapter));
        mocaToken.mint(10 ether);

        // gas
        vm.deal(userA, 10 ether);
    }
}

contract StateRateLimitsTest is StateRateLimits {

    function testCannotExceedInboundLimits() public {

        assert(mocaToken.balanceOf(userA) == 10 ether);

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(MocaTokenAdapter.ExceedInboundLimit.selector, 5 ether, 10 ether));
        
        mocaTokenAdapter.credit(userA, 10 ether, 1);
    }

    function testCannotExceedOutboundLimits() public {

        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: 1,                                                               // Destination endpoint ID.
            to: bytes32(uint256(uint160(userA))),  // Recipient address.
            amountLD: 10 ether,                                                                   // Amount to send in local decimals        
            minAmountLD: 10 ether,                                                                // Minimum amount to send in local decimals.
            extraOptions: nullBytes,                                                             // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: nullBytes,                                                                // The composed message for the send() operation.
            oftCmd: nullBytes                                                                    // The OFT command to be executed, unused in default OFT implementations.
        });

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(MocaTokenAdapter.ExceedOutboundLimit.selector, 5 ether, 10 ether));
        mocaTokenAdapter.send(sendParam, MessagingFee({nativeFee: 1 ether, lzTokenFee: 0}), userA);
    }

    function testInboundLimitsWithinPeriod() public {
        
        uint256 initialReceiveTokenAmount = mocaTokenAdapter.receivedTokenAmounts(1);
        uint256 initialReceiveTimestamp = mocaTokenAdapter.lastReceivedTimestamps(1);
        assertTrue(initialReceiveTimestamp == 0);        
        assertTrue(initialReceiveTokenAmount == 0);  

        vm.warp(5);

        vm.prank(userA);        
        uint256 amountReceived = mocaTokenAdapter.credit(userA, 5 ether, 1);
        assertTrue(amountReceived == 0 ether);

        // reflects minting of new tokens
        assertTrue(mocaToken.balanceOf(userA) == 15 ether);
        
        // check timestamp and cumulative received amount UNCHANGED. 
        assertTrue(mocaTokenAdapter.receivedTokenAmounts(1) == initialReceiveTokenAmount + 5 ether);
        assertTrue(mocaTokenAdapter.lastReceivedTimestamps(1) == initialReceiveTimestamp);     
    }

    function testInboundLimitsBeyondPeriod() public {
        
        uint256 initialReceiveTokenAmount = mocaTokenAdapter.receivedTokenAmounts(srcid);
        uint256 initialReceiveTimestamp = mocaTokenAdapter.lastReceivedTimestamps(srcid);
        assertTrue(initialReceiveTimestamp == 0);        
        assertTrue(initialReceiveTokenAmount == 0);        

        vm.warp(86401);

        assertTrue(block.timestamp > initialReceiveTimestamp);
        assertTrue(mocaTokenAdapter.inboundLimits(srcid) == 5 ether);

        vm.prank(userA);        
        uint256 amountReceived = mocaTokenAdapter.credit(userA, 5 ether, 1);
        assertTrue(amountReceived == 0 ether);

        // reflects minting of new tokens
        assertTrue(mocaToken.balanceOf(userA) == 15 ether);
        
        assertTrue(mocaTokenAdapter.receivedTokenAmounts(srcid) == initialReceiveTokenAmount + 5 ether);
        assertTrue(mocaTokenAdapter.lastReceivedTimestamps(srcid) == 86401);     
    }

    function testOutboundLimitsWithinPeriod() public {
        
        uint256 initialSentTokenAmount = mocaTokenAdapter.sentTokenAmounts(dstid);
        uint256 initialSentTimestamp = mocaTokenAdapter.lastSentTimestamps(dstid);
        assertTrue(initialSentTimestamp == 0);        
        assertTrue(initialSentTokenAmount == 0); 

        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: dstid,                                                                        // Destination endpoint ID.
            to: peer,                                                                             // Recipient address.
            amountLD: 5 ether,                                                                   // Amount to send in local decimals        
            minAmountLD: 5 ether,                                                                // Minimum amount to send in local decimals.
            extraOptions: nullBytes,                                                             // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: nullBytes,                                                                // The composed message for the send() operation.
            oftCmd: nullBytes                                                                    // The OFT command to be executed, unused in default OFT implementations.
        });

        vm.warp(5);

        vm.prank(userA);
        mocaTokenAdapter.send(sendParam, MessagingFee({nativeFee: 0 ether, lzTokenFee: 0}), payable(userA));

        assertTrue(mocaToken.balanceOf(userA) == 5 ether);

        // check timestamp and cumulative received amount UNCHANGED. 
        assertTrue(mocaTokenAdapter.sentTokenAmounts(dstid) == initialSentTokenAmount + 5 ether);
        assertTrue(mocaTokenAdapter.lastSentTimestamps(dstid) == initialSentTimestamp); 
    }

    function testOutboundLimitsBeyondPeriod() public {
        
        uint256 initialSentTokenAmount = mocaTokenAdapter.sentTokenAmounts(dstid);
        uint256 initialSentTimestamp = mocaTokenAdapter.lastSentTimestamps(dstid);
        assertTrue(initialSentTimestamp == 0);        
        assertTrue(initialSentTokenAmount == 0);        

        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: dstid,                                                                        // Destination endpoint ID.
            to: peer,                                                                             // Recipient address.
            amountLD: 5 ether,                                                                   // Amount to send in local decimals        
            minAmountLD: 5 ether,                                                                // Minimum amount to send in local decimals.
            extraOptions: nullBytes,                                                             // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: nullBytes,                                                                // The composed message for the send() operation.
            oftCmd: nullBytes                                                                    // The OFT command to be executed, unused in default OFT implementations.
        });

        vm.warp(86400);

        vm.prank(userA);
        mocaTokenAdapter.send(sendParam, MessagingFee({nativeFee: 0 ether, lzTokenFee: 0}), payable(userA));

        assertTrue(mocaToken.balanceOf(userA) == 5 ether);

        // check timestamp and cumulative received amount UNCHANGED. 
        assertTrue(mocaTokenAdapter.sentTokenAmounts(dstid) == initialSentTokenAmount + 5 ether);
        assertTrue(mocaTokenAdapter.lastSentTimestamps(dstid) == 86400);     
    }



    function testWhitelistInbound() public {
        
        vm.expectEmit(false, false, false, false);
        emit SetWhitelist(userA, true);

        vm.prank(deployer);
        mocaTokenAdapter.setWhitelist(userA, true);

        uint256 initialReceiveTokenAmount = mocaTokenAdapter.receivedTokenAmounts(1);
        uint256 initialReceiveTimestamp = mocaTokenAdapter.lastReceivedTimestamps(1);
                
        vm.prank(userA);        
        uint256 amountReceived = mocaTokenAdapter.credit(userA, 10 ether, 1);

        // NOTE: WHY DOES IT RETURN 0?
        assertTrue(amountReceived == 0 ether);
        
        // reflects minting of new tokens
        assertTrue(mocaToken.balanceOf(userA) == 20 ether);

        // check timestamp and cumulative received amount UNCHANGED. 
        assertTrue(mocaTokenAdapter.receivedTokenAmounts(1) == initialReceiveTokenAmount);
        assertTrue(mocaTokenAdapter.lastReceivedTimestamps(1) == initialReceiveTimestamp);
    }

    function testWhitelistOutbound() public {
        vm.prank(deployer);
        mocaTokenAdapter.setWhitelist(userA, true);

        uint256 initialSentTokenAmount = mocaTokenAdapter.sentTokenAmounts(dstid);
        uint256 initialSentTimestamp = mocaTokenAdapter.lastSentTimestamps(dstid);

        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: dstid,                                                                        // Destination endpoint ID.
            to: peer,                                                                             // Recipient address.
            amountLD: 10 ether,                                                                   // Amount to send in local decimals        
            minAmountLD: 10 ether,                                                                // Minimum amount to send in local decimals.
            extraOptions: nullBytes,                                                             // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: nullBytes,                                                                // The composed message for the send() operation.
            oftCmd: nullBytes                                                                    // The OFT command to be executed, unused in default OFT implementations.
        });

        vm.prank(userA);
        mocaTokenAdapter.send(sendParam, MessagingFee({nativeFee: 0 ether, lzTokenFee: 0}), payable(userA));

        // 0, since they were "sent" and therefore burnt/locked
        assertTrue(mocaToken.balanceOf(userA) == 0);

        // check timestamp and cumulative received amount UNCHANGED. 
        assertTrue(mocaTokenAdapter.sentTokenAmounts(dstid) == initialSentTokenAmount);
        assertTrue(mocaTokenAdapter.lastSentTimestamps(dstid) == initialSentTimestamp);
    }

    function testOperatorCanSetPeers() public {
        
        vm.expectEmit(false, false, false, false);
        emit PeerSet(1, bytes32(uint256(uint160(userA))));
        
        vm.prank(operator);
        mocaTokenAdapter.setPeer(1, bytes32(uint256(uint160(userA))));
        
        // check state
        assertTrue(mocaTokenAdapter.peers(1) == bytes32(uint256(uint160(userA))));
    }

    function testUserCannotSetPeers() public {
        
        vm.prank(userA);
        vm.expectRevert("Not Operator");
        mocaTokenAdapter.setPeer(1, bytes32(uint256(uint160(userA))));
    }
}