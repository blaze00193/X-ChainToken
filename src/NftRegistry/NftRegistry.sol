// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { OApp, Origin, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// issues
contract NftRegistry is OApp {

    address public pool;

    struct UserData {
        uint128 totalLocked;
        uint128 totalStaked;
    }

    mapping(address user => UserData userData) public users;

    // events
    event PoolUpdated(address indexed newPool);
    event LockerUpdated(address indexed newLocker);

    event NftRegisted(address indexed user, uint256 indexed totalLocked);
    event NftReleased(address indexed user, uint256 indexed totalLocked);

    event NftStaked(address indexed user, uint256 indexed totalLocked, uint256 indexed totalStaked);
    event NftUnstaked(address indexed user, uint256 indexed totalStaked);

//-------------------------------constructor-------------------------------------------
    constructor(address _endpoint, address _owner, address pool_) OApp(_endpoint, _owner) Ownable(_owner) {
        pool = pool_;
    }

    /*//////////////////////////////////////////////////////////////
                                 LOCKER
    //////////////////////////////////////////////////////////////*/

    // only callable by LZ
    function _register(address onBehalfOf) internal {
        // cache 
        UserData memory user = users[onBehalfOf];

        // increment
        ++user.totalLocked;
        
        // update storage
        users[onBehalfOf] = user;
        
        emit NftRegisted(onBehalfOf, user.totalLocked);
    }
    
    // calls NftLocker on Ethereum. called by user
    function release(uint32 _dstEid, bytes calldata _options) external {
        _release(msg.sender, _dstEid, _options);
    }
    
    // admin to call deregister on a specific user in special cases 
    function release(address onBehalfOf, uint32 _dstEid, bytes calldata _options) external onlyOwner {
        _release(onBehalfOf, _dstEid, _options);
    }

    // calls NftLocker on Ethereum.
    function _release(address onBehalfOf, uint32 _dstEid, bytes calldata _options) internal {
        
        // cache 
        UserData memory user = users[onBehalfOf];
        
        // decrement
        --user.totalLocked;

        emit NftReleased(onBehalfOf, user.totalLocked);

        // Encodes message as bytes
        bytes memory _payload = abi.encode(onBehalfOf);

        //lz
        _lzSend(_dstEid, _payload, _options, MessagingFee(msg.value, 0), payable(msg.sender));
    }

//-------------------------------------------------------------------------------------

    /*//////////////////////////////////////////////////////////////
                                  POOL
    //////////////////////////////////////////////////////////////*/
   
    function setPool(address pool_) external onlyOwner {
        pool = pool_;
        emit PoolUpdated(pool_);
    }

    ///@dev only callable by pool
    function recordStake(address onBehalfOf, uint256 amount) external {
        require(msg.sender == pool, "Only pool");

        // cache 
        UserData memory user = users[onBehalfOf];

        // check available
        uint256 available = user.totalLocked - user.totalStaked;
        require(available >= amount, "Incorrect amount");

        // increment
        ++user.totalStaked;

        // update storage
        users[onBehalfOf] = user;
        
        emit NftStaked(onBehalfOf, user.totalLocked, user.totalStaked);
    }

    ///@dev only callable by pool
    function recordUnstake(address onBehalfOf, uint128 amount) external {
        require(msg.sender == pool, "Only pool");

        // cache 
        UserData storage user = users[onBehalfOf];
        uint128 totalStaked = user.totalStaked;

        // check available
        require(totalStaked >= amount, "Incorrect amount");

        // derement
        --totalStaked;

        // update storage
        users[onBehalfOf].totalStaked = totalStaked;
        
        emit NftUnstaked(onBehalfOf, totalStaked);
    }

//-------------------------------------------------------------------------------------


    /*//////////////////////////////////////////////////////////////
                               LAYERZERO
    //////////////////////////////////////////////////////////////*/

    /** 
     * @dev Quotes the gas needed to pay for the full omnichain transaction.
     * @param _dstEid Destination chain's endpoint ID.
     * @param _options // Message execution options (e.g., gas to use on destination).
     * @param onBehalfOf Nft owner address
     * @param tokenId Nft tokenId
     */
    function send(uint32 _dstEid, bytes calldata _options, address onBehalfOf, uint256 tokenId) external payable {
        
        // Encodes message as bytes
        bytes memory _payload = abi.encode(tokenId, onBehalfOf);

        _lzSend(_dstEid, _payload, _options, 
            MessagingFee(msg.value, 0),     // Fee struct containing native gas and ZRO token.
            payable(msg.sender)             // The refund address in case the send call reverts.
        );
    }


    /** Note: there exist lzReceive as public function that calls _lzReceive
     * @param origin struct containing info about the message sender
     * @param guid global packet identifier
     * @param payload message payload being received
     * @param executor the Executor address.
     * @param extraData arbitrary data appended by the Executor
     */
    function _lzReceive(Origin calldata origin, bytes32 guid, bytes calldata payload, address executor, bytes calldata extraData) internal override {
        
        // tokendId, owner
        address owner = abi.decode(payload, (address));

        // update
        _register(owner);
    }

}








/**
1) NFT registry does not issue erc20 token.
    no. of nfts per user recorded in mapping
    when user wishes to stake nft, router calls registry to check if there are available nfts
    Once an nft is staked, registry must be updated by the stakingPool, to "lock" nfts
     increment lockAmount
     decrement availableAmount

Since no tokens are used in this approach, users will not be able to "see" anything
in their metamask wallet

2) NFT registry issues erc20 token.
    On locking the nFT on mainnet, registry issues bridgedNftToken to user, on polygon
    user can stake bridgedNFTToken into stakingPool
    on staking, user transfers bridgedNftToken to pool, and receives stkNftToken.

    This means tt while registry can inherit bridgedNFTToken.
    We will need a standalone erc20 token contract for stkNftToken.
    stakinPool cannot inherit this, since it already inherits stkMocaToken.

    registry mints user bridgedNFTToken
    bridgedNFTToken transferred to stakingPool
    - bridgedNFTToken must be freely mint/burn and transferable

    stakinPool mints/burns stkNftToken
    - stkNftToken can be non-transferable.

bridgedNFTToken will need to be ERC20Permit, for gassless transfer on staking.

 */
