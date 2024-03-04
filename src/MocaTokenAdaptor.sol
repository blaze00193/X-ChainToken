// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { OFTAdapter } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// SendParam
import "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
//import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { OApp, Origin } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";


//Note: Adaptor is only to be deployed on the home chain where the token contract was originally deployed. 
//      Must approve OFT Adapter as a spender of your ERC20 token.
contract MocaTokenAdaptor is OFTAdapter, Pausable {

    /**
     * @param token a deployed, already existing ERC20 token address
     * @param layerZeroEndpoint local endpoint address
     * @param delegate The address capable of making OApp configurations inside of the endpoint.
     * @param owner token owner
     */
    constructor(address token, address layerZeroEndpoint, address delegate, address owner) 
        OFTAdapter(token, layerZeroEndpoint, delegate) Ownable(owner) {
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


/**

This standard has already implemented OApp related functions like _lzSend and _lzReceive.
 Instead, you will override and use _debit and _credit when writing your own custom OFT logic.

Token Supply Cap
 default OFT Standard has a max token supply 2^64 - 1
 cos on-EVM environments use uint64
 This ensures that token transfers won't fail due to a loss of precision or unexpected balance conversions
 
Shared Decimals
 By default, an OFT has 6 sharedDecimals, which is optimal for most ERC20 use cases that use 18 decimals.

Owner and delegate
 contract owner is set as the delegate in cosntructor
 delegate has the ability to handle various critical tasks such as setting configurations and MessageLibs
 delegate can be changed via
    
    function setDelegate(address _delegate) public onlyOwner {
        endpoint.setDelegate(_delegate);
    }

 delegate can be assigned to implement custom configurations on behalf of the contract owner.
 

 */