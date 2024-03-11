// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { OFTAdapter } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// LZ Structs
import { Origin } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { SendParam, MessagingFee, MessagingReceipt, OFTReceipt } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";


//Note: Adapter is only to be deployed on the home chain where the token contract was originally deployed. 
//      Must approve OFT Adapter as a spender of your ERC20 token.
contract MocaTokenAdapter is OFTAdapter {

    // Outbound limits
    mapping(uint32 chainID => uint256 outboundLimit) public outboundLimits;
    mapping(uint32 chainID => uint256 sentTokenAmount) public sentTokenAmounts;
    mapping(uint32 chainID => uint256 lastSentTimestamp) public lastSentTimestamps;

    // Inbound limits
    mapping(uint32 chainID => uint256 inboundLimit) public inboundLimits;
    mapping(uint32 chainID => uint256 receivedTokenAmount) public receivedTokenAmounts;
    mapping(uint32 chainID => uint256 lastReceivedTimestamp) public lastReceivedTimestamps;

    // If an address is whitelisted, limit checks are skipped
    mapping(address addr => bool isWhitelisted) public whitelist;

    // if an address is an operator is can disconnect/connect bridges via setPeers
    mapping(address addr => bool isOperator) public operators;

    // events 
    event SetOutboundLimit(uint32 indexed chainId, uint256 limit);
    event SetInboundLimit(uint32 indexed chainId, uint256 limit);
    event SetWhitelist(address indexed addr, bool isWhitelist);
    event SetOperator(address indexed addr, bool isWhitelist);

    // errors
    error ExceedInboundLimit(uint256 limit, uint256 amount);
    error ExceedOutboundLimit(uint256 limit, uint256 amount);

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
                              RATE LIMITS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Owner to set the max daily limit on onbound x-chain transfers
     * @param chainId Destination chainId 
     * @param limit Daily outbound limit
     */
    function setOutboundLimit(uint32 chainId, uint256 limit) external onlyOwner {
        outboundLimits[chainId] = limit;
        emit SetOutboundLimit(chainId, limit);
    }

    /**
     * @dev Owner to set the max daily limit on inbound x-chain transfers
     * @param chainId Destination chainId 
     * @param limit Daily inbound limit
     */
    function setInboundLimit(uint32 chainId, uint256 limit) external onlyOwner {
        inboundLimits[chainId] = limit;
        emit SetInboundLimit(chainId, limit);
    }

    /**
     * @dev Owner to set whitelisted addresses - limits do not apply to these addresses 
     * @param addr address
     * @param isWhitelisted true/false
     */
    function setWhitelist(address addr, bool isWhitelisted) external onlyOwner {
        whitelist[addr] = isWhitelisted;
        emit SetWhitelist(addr, isWhitelisted);
    }

    /**
     * @dev Owner to set operator addresses - these addresses can call setPeers
     * @param addr address
     * @param isOperator true/false
     */
    function setOperator(address addr, bool isOperator) external onlyOwner {
        operators[addr] = isOperator;
        emit SetOperator(addr, isOperator);
    }

    /**
     * @dev Overwrite _debit to implement rate limits.
     * @dev Burns tokens from the sender's specified balance.
     * @param amountLD The amount of tokens to send in local decimals.
     * @param minAmountLD The minimum amount to send in local decimals.
     * @param dstEid The destination chain ID.
     * @return amountSentLD The amount sent in local decimals.
     * @return amountReceivedLD The amount received in local decimals on the remote.
     */
    function _debit(uint256 amountLD, uint256 minAmountLD, uint32 dstEid) internal override returns (uint256, uint256) {
        // _burn(msg.sender, amountSentLD)
        (uint256 amountSentLD, uint256 amountReceivedLD) = super._debit(amountLD, minAmountLD, dstEid);

        // whitelisted addresses have no limits
        if (whitelist[msg.sender]) return (amountSentLD, amountReceivedLD);

        uint256 sentTokenAmount;
        uint256 lastSentTimestamp = lastSentTimestamps[dstEid];
        uint256 currTimestamp = block.timestamp;
        
        // Round down timestamps to the nearest day. 
        // If these two values are different, it means at least one full day has passed since the last transaction.
        if ((currTimestamp / (1 days)) > (lastSentTimestamp / (1 days))) {
            sentTokenAmount = amountSentLD;        
        } else {
            // sentTokenAmount = recentSentAmount + incomingSendAmount
            sentTokenAmount = sentTokenAmounts[dstEid] + amountSentLD;
        }

        // check against outboundLimit
        uint256 outboundLimit = outboundLimits[dstEid];
        if (sentTokenAmount > outboundLimit) revert ExceedOutboundLimit(outboundLimit, sentTokenAmount);

        // update storage
        sentTokenAmounts[dstEid] = sentTokenAmount;
        lastSentTimestamps[dstEid] = currTimestamp;

        return (amountSentLD, amountReceivedLD);
    }

    
    /**
     * @dev Credits tokens to the specified address.
     * @param to The address to credit the tokens to.
     * @param amountLD The amount of tokens to credit in local decimals.
     * @param srcEid The source chain ID.
     * @return amountReceivedLD The amount of tokens ACTUALLY received in local decimals.
     */
    function _credit(address to, uint256 amountLD, uint32 srcEid) internal override returns (uint256) {
        
        uint256 amountReceivedLD = super._credit(to, amountLD, srcEid);

        // whiteslisted address have no limits
        if (whitelist[to]) return amountReceivedLD;


        uint256 receivedTokenAmount;
        uint256 lastReceivedTimestamp = lastReceivedTimestamps[srcEid];
        uint256 currTimestamp = block.timestamp;

        // Round down timestamps to the nearest day. 
        // If these two values are different, it means at least one full day has passed since the last transaction.
        if ((currTimestamp / (1 days)) > (lastReceivedTimestamp / (1 days))) {
            receivedTokenAmount = amountReceivedLD;
        } else {
            receivedTokenAmount = receivedTokenAmounts[srcEid] + amountReceivedLD;
        }

        // ensure limit not exceeded
        uint256 inboundLimit = inboundLimits[srcEid];
        if (receivedTokenAmount > inboundLimit) revert ExceedInboundLimit(inboundLimit, receivedTokenAmount);

        // update storage
        receivedTokenAmounts[srcEid] = receivedTokenAmount;
        lastReceivedTimestamps[srcEid] = currTimestamp;

        return amountReceivedLD;
    } 


    /*//////////////////////////////////////////////////////////////
                              LZ OVERRIDE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the peer address (OApp instance) for a corresponding endpoint.
     * @param _eid The endpoint ID.
     * @param _peer The address of the peer to be associated with the corresponding endpoint.
     * @dev Only an operator of the OApp can call this function.
     * @dev Indicates that the peer is trusted to send LayerZero messages to this OApp.
     * @dev Set this to bytes32(0) to remove the peer address.
     * @dev Peer is a bytes32 to accommodate non-evm chains.
     */
    function setPeer(uint32 _eid, bytes32 _peer) public override {
        require(operators[msg.sender] == true || msg.sender == owner(), "Not Operator");

        peers[_eid] = _peer;
        emit PeerSet(_eid, _peer);
    }



}
