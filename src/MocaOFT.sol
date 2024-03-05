// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { EIP3009 } from "./EIP3009.sol";
import { EIP712 } from "./utils/EIP712.sol";

// SendParam
import "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { Origin } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";


//Note: To be deployed everywhere else, outside of the home chain
//      18 dp
contract MocaOFT is OFT, EIP3009, Pausable {

    string internal constant _version = "v1";


    /**
     * @param name token name
     * @param symbol token symbol
     * @param lzEndpoint LayerZero Endpoint address
     * @param delegate The address capable of making OApp configurations inside of the endpoint.
     * @param owner token owner
     */
    constructor(string memory name, string memory symbol, address lzEndpoint, address delegate, address owner) 
        OFT(name, symbol, lzEndpoint, delegate) Ownable(owner) {

        _DOMAIN_SEPARATOR = EIP712.makeDomainSeparator(name, _version);
    }

    /*//////////////////////////////////////////////////////////////
                                 EIP721
    //////////////////////////////////////////////////////////////*/

    function _domainSeparator() internal override view returns (bytes32) {
        return block.chainid == _DEPLOYMENT_CHAINID ? _DOMAIN_SEPARATOR : EIP712.makeDomainSeparator(name(), _version);

    }

    /*//////////////////////////////////////////////////////////////
                              LZ OVERRIDE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Override to add whenNotPaused modifier.
               original send() is external virtual. So we cannot call super.send()
               Hence, we copy the body of the fn into this. 
     * @dev Executes the send operation.
     * @param _sendParam The parameters for the send operation.
     * @param _fee The calculated fee for the send() operation.
     *      - nativeFee: The native fee.
     *      - lzTokenFee: The lzToken fee.
     * @param _refundAddress The address to receive any excess funds.
     * @return msgReceipt The receipt for the send operation.
     * @return oftReceipt The OFT receipt information.
     *
     * @dev MessagingReceipt: LayerZero msg receipt
     *  - guid: The unique identifier for the sent message.
     *  - nonce: The nonce of the sent message.
     *  - fee: The LayerZero fee incurred for the message.
     */
     
    function send(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress)
        external payable override whenNotPaused returns(MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
            
        // "super.send()"

        // @dev Applies the token transfers regarding this send() operation.
        // - amountSentLD is the amount in local decimals that was ACTUALLY sent from the sender.
        // - amountReceivedLD is the amount in local decimals that will be credited to the recipient on the remote OFT instance.
        (uint256 amountSentLD, uint256 amountReceivedLD) = _debit(
            _sendParam.amountLD,
            _sendParam.minAmountLD,
            _sendParam.dstEid
        );

        // @dev Builds the options and OFT message to quote in the endpoint.
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, amountReceivedLD);

        // @dev Sends the message to the LayerZero endpoint and returns the LayerZero msg receipt.
        msgReceipt = _lzSend(_sendParam.dstEid, message, options, _fee, _refundAddress);
        // @dev Formulate the OFT receipt.
        oftReceipt = OFTReceipt(amountSentLD, amountReceivedLD);

        emit OFTSent(msgReceipt.guid, _sendParam.dstEid, msg.sender, amountSentLD);
    }


    /**
     * @dev Internal function to handle the receive on the LayerZero endpoint.
     * @param _origin The origin information.
     *  - srcEid: The source chain endpoint ID.
     *  - sender: The sender address from the src chain.
     *  - nonce: The nonce of the LayerZero message.
     * @param _guid The unique identifier for the received LayerZero message.
     * @param _message The encoded message.
     * @dev _executor The address of the executor.
     * @dev _extraData Additional data.
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address unnamedAddress,      /*_executor*/ // @dev unused in the default implementation.
        bytes calldata unnamedBytes  /*_extraData*/ // @dev unused in the default implementation.
    ) internal override whenNotPaused {

        super._lzReceive(_origin, _guid, _message, unnamedAddress, unnamedBytes);
    }


    /*//////////////////////////////////////////////////////////////
                             ERC20 OVERRIDE
    //////////////////////////////////////////////////////////////*/

    ///@dev Override to add whenNotPaused modifier
    function transfer(address to, uint256 value) public override whenNotPaused returns (bool) {
        super.transfer(to, value);
    }

    ///@dev Override to add whenNotPaused modifier
    function transferFrom(address from, address to, uint256 value) public override whenNotPaused returns (bool) {   
        super.transferFrom(from, to, value);
    }

    ///@dev Override to add whenNotPaused modifier
    function approve(address spender, uint256 value) public override whenNotPaused returns (bool) {
        super.approve(spender, value);
    }

    /*//////////////////////////////////////////////////////////////
                                EIP3009
    //////////////////////////////////////////////////////////////*/

    
    /**
     * @notice Execute a transfer with a signed authorization
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function transferWithAuthorization(address from, address to, uint256 value, uint256 validAfter, uint256 validBefore, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external {
        _transferWithAuthorization(
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    /**
     * @notice Attempt to cancel an authorization
     * @dev Works only if the authorization is not yet used.
     * EOA wallet signatures should be packed in the order of r, s, v.
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external {
        _cancelAuthorization(authorizer, nonce, v, r, s);
    }

    /**
     * @notice Receive a transfer with a signed authorization from the payer
     * @dev This has an additional check to ensure that the payee's address
     * matches the caller of this function to prevent front-running attacks.
     * EOA wallet signatures should be packed in the order of r, s, v.
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {

        _receiveWithAuthorization(
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    /*//////////////////////////////////////////////////////////////
                                PAUSABLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

}