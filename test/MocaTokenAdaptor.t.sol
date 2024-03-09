// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";

import "test/mocks/MockTokenAdaptor.sol";
import {MocaOFTMock} from "./mocks/MocaOFTMock.sol";
import {EndpointV2Mock} from "./mocks/EndpointV2Mock.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";


// SendParam
import "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Origin } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";


abstract contract StateDeployed is Test {
    
    MockTokenAdaptor public mocaTokenAdaptor;
    EndpointV2Mock public lzMock;
    MocaOFTMock public mocaToken;

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
        mocaToken = new MocaOFTMock(name, symbol, address(lzMock), deployer, deployer);
        mocaTokenAdaptor = new MockTokenAdaptor(address(mocaToken), address(lzMock), delegate, deployer);

        vm.stopPrank();
    }
}

abstract contract StateRateLimits is StateDeployed {
    
    uint32 public dstid = 1;
    bytes32 public peer = bytes32(uint256(uint160(treasury)));  

    function setUp() virtual override public {
        super.setUp();

        vm.startPrank(deployer);

        dstid = 1;
        peer = bytes32(uint256(uint160(treasury)));  
        mocaTokenAdaptor.setPeer(dstid, peer);
        
        mocaTokenAdaptor.setOutboundCap(1, 1 ether);
        mocaTokenAdaptor.setInboundCap(1, 1 ether);
        mocaTokenAdaptor.setOperator(operator, true);
    
        vm.stopPrank();
        
        vm.startPrank(userA);
            mocaToken.mint(10 ether);
            mocaToken.approve(address(mocaTokenAdaptor), 10 ether);
        vm.stopPrank();

        vm.prank(address(mocaTokenAdaptor));
        mocaToken.mint(10 ether);

        // gas
        vm.deal(userA, 10 ether);
    }
}

contract StateRateLimitsTest is StateRateLimits {

    function testCannotExceedInboundLimits() public {

        assert(mocaToken.balanceOf(userA) == 10 ether);

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(MocaTokenAdaptor.ExceedInboundLimit.selector, 1 ether, 10 ether));
        
        mocaTokenAdaptor.credit(userA, 10 ether, 1);
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
        vm.expectRevert(abi.encodeWithSelector(MocaTokenAdaptor.ExceedOutboundLimit.selector, 1 ether, 10 ether));
        mocaTokenAdaptor.send(sendParam, MessagingFee({nativeFee: 1 ether, lzTokenFee: 0}), userA);
    }

    function testWhitelistInbound() public {
        
        vm.expectEmit(false, false, false, false);
        emit SetWhitelist(userA, true);

        vm.prank(deployer);
        mocaTokenAdaptor.setWhitelist(userA, true);

        uint256 initialReceiveTokenAmount = mocaToken.receivedTokenAmounts(1);
        uint256 initialReceiveTimestamp = mocaToken.lastReceivedTimestamps(1);
                
        vm.prank(userA);        
        uint256 amountReceived = mocaTokenAdaptor.credit(userA, 10 ether, 1);

        // NOTE: WHY DOES IT RETURN 0?
        assertTrue(amountReceived == 0 ether);
        
        // reflects minting of new tokens
        assertTrue(mocaToken.balanceOf(userA) == 20 ether);

        // check timestamp and cumulative received amount UNCHANGED. 
        assertTrue(mocaToken.receivedTokenAmounts(1) == initialReceiveTokenAmount);
        assertTrue(mocaToken.lastReceivedTimestamps(1) == initialReceiveTimestamp);
    }

    function testWhitelistOutbound() public {
        vm.prank(deployer);
        mocaTokenAdaptor.setWhitelist(userA, true);

        uint256 initialSentTokenAmount = mocaToken.sentTokenAmounts(dstid);
        uint256 initialSentTimestamp = mocaToken.lastSentTimestamps(dstid);

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
        mocaTokenAdaptor.send(sendParam, MessagingFee({nativeFee: 0 ether, lzTokenFee: 0}), payable(userA));

        // 0, since they were "sent" and therefore burnt/locked
        assertTrue(mocaToken.balanceOf(userA) == 0);

        // check timestamp and cumulative received amount UNCHANGED. 
        assertTrue(mocaToken.sentTokenAmounts(dstid) == initialSentTokenAmount);
        assertTrue(mocaToken.lastSentTimestamps(dstid) == initialSentTimestamp);
    }

    function testOperatorCanSetPeers() public {
        
        vm.expectEmit(false, false, false, false);
        emit PeerSet(1, bytes32(uint256(uint160(userA))));
        
        vm.prank(operator);
        mocaTokenAdaptor.setPeer(1, bytes32(uint256(uint160(userA))));
        
        // check state
        assertTrue(mocaTokenAdaptor.peers(1) == bytes32(uint256(uint160(userA))));
    }

    function testUserCannotSetPeers() public {
        
        vm.prank(userA);
        vm.expectRevert("Not Operator");
        mocaTokenAdaptor.setPeer(1, bytes32(uint256(uint160(userA))));
    }
}
 /*
contract StateDeployedTestPausable is StateDeployed {

    function testUserCannotCallPause() public {
        
        assertEq(mocaTokenAdaptor.paused(), false);
        
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userA));
        mocaTokenAdaptor.pause();

        assertEq(mocaTokenAdaptor.paused(), false);
    }

    function testOwnerCanCallPause() public {
        
        assertEq(mocaTokenAdaptor.paused(), false);

        vm.prank(deployer);
        mocaTokenAdaptor.pause();

        assertEq(mocaTokenAdaptor.paused(), true);

        vm.prank(deployer);
        mocaTokenAdaptor.unpause();

        assertEq(mocaTokenAdaptor.paused(), false);
    }

    function testPausedSend() public {

        vm.prank(deployer);
        mocaTokenAdaptor.pause();


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
        mocaTokenAdaptor.send{value: messagingFee.nativeFee}(sendParam, messagingFee, payable(deployer));
    }

    function testPauseLzReceive() public {
        vm.prank(deployer);
        mocaTokenAdaptor.pause();


        Origin memory _origin;
        bytes32 _guid;
        bytes memory _message;
        address unnamedAddress;  
        bytes memory unnamedBytes;

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        mocaTokenAdaptor.mockLzReceive(_origin, _guid, _message, unnamedAddress, unnamedBytes);
    }

}
*/