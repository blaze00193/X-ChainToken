// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";

import "test/mocks/MockTokenAdaptor.sol";
import {MocaOFTMock} from "./mocks/MocaOFTMock.sol";
import {EndpointV2Mock} from "./mocks/EndpointV2Mock.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
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

    function setUp() public {

        //users
        userA = makeAddr('userA');
        delegate = makeAddr('delegate');

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