// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { OFTAdapter } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// SendParam
import "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";


//Note: Adaptor is only to be deployed on the home chain where the token contract was originally deployed. 
//      Must approve OFT Adapter as a spender of your ERC20 token.
contract MocaTokenAdaptor is OFTAdapter, Pausable {

    /**
     * @param _token a deployed, already existing ERC20 token address
     * @param _layerZeroEndpoint local endpoint address
     * @param _delegate The address capable of making OApp configurations inside of the endpoint.
     * @param _owner token owner
     */
    constructor(address _token, address _layerZeroEndpoint, address _delegate, address _owner) 
        OFTAdapter(_token, _layerZeroEndpoint, _delegate) Ownable(_owner) {
    }

    /*//////////////////////////////////////////////////////////////
                              LZ OVERRIDE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Added whenNotPaused modifier 
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
    function send(
        SendParam calldata _sendParam, 
        MessagingFee calldata _fee, 
        address _refundAddress
        ) external payable override whenNotPaused returns(MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
        
        super.send(_sendParam, _fee, _refundAddress);
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