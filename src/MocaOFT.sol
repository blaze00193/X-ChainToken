// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { OFT } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { EIP3009 } from "./EIP3009.sol";
import { EIP712 } from "./utils/EIP712.sol";

// LZ Structs
import { Origin } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { SendParam, MessagingFee, MessagingReceipt, OFTReceipt } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";


//Note: To be deployed everywhere else, outside of the home chain
//      18 dp
contract MocaOFT is OFT, EIP3009 {

    string internal constant _version = "v1";

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
                              RATE LIMITS
    //////////////////////////////////////////////////////////////*/

    function setOutboundCap(uint32 chainId, uint256 limit) external onlyOwner {
        outboundLimits[chainId] = limit;
        emit SetOutboundLimit(chainId, limit);
    }

    function setInboundCap(uint32 chainId, uint256 limit) external onlyOwner {
        inboundLimits[chainId] = limit;
        emit SetInboundLimit(chainId, limit);
    }

    function setWhitelist(address addr, bool isWhitelisted) external onlyOwner {
        whitelist[addr] = isWhitelisted;
        emit SetWhitelist(addr, isWhitelisted);
    }

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

        // check against outboundCap
        uint256 outboundCap = outboundLimits[dstEid];
        if (sentTokenAmount > outboundCap) revert ExceedOutboundLimit(outboundCap, sentTokenAmount);

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

        // ensure cap not exceeded
        uint256 inboundCap = inboundLimits[srcEid];
        if (receivedTokenAmount > inboundCap) revert ExceedInboundLimit(inboundCap, receivedTokenAmount);

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


}