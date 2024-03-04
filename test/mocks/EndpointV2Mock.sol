// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

// SendParam
import "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";


contract EndpointV2Mock {

    function setDelegate(address /*_delegate*/) external{}

    function send(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress) external payable{}

}