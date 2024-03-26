/*
abstract contract DvnData {
    
    address public layerZero_mainnet = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
    address public layerZero_polygon = 0x23DE2FE932d9043291f870324B74F820e11dc81A;
    
    // same address for both mainnet and polygon
    address public gcp = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc;

    address public animoca_mainnet = 0x7E65BDd15C8Db8995F80aBf0D6593b57dc8BE437;
    address public animoca_polygon = 0xa6F5DDBF0Bd4D03334523465439D301080574742;
    
    address public nethermind_mainnet = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5;
    address public nethermind_polygon = 0x31F748a368a893Bdb5aBB67ec95F232507601A73;

    //..............................................................................

    // testnet addressses 
    address public layerZero_sepolia = 0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193;
    address public layerZero_polygon = 0x67a822F55C5F6E439550b9C4EA39E406480a40f3;

    address public nethermind_testnet_ethereum = 0x715A4451Be19106BB7CefD81e507813E23C30768;
    address public nethermind_testnet_polygon = 0xC460CEcfcc7A69665cCd41Ebf25Dd2572c18f657;

    //..............................................................................

    // https://docs.layerzero.network/contracts/messagelib-addresses
    address public send302 = 0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE;
    address public receive302 = 0xdAf00F5eE2158dD58E0d3857851c432E34A3A851;
}

contract SetDvnHome is State, Script, DvnData {

    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // config bytes
        bytes memory configBytes;
            
            uint64 confirmations = 15;        // confirmation on polygon 
            
            uint8 optionalDVNCount; 
            uint8 optionalDVNThreshold; 
            address[] memory optionalDVNs;

            uint8 requiredDVNCount = 4; 
            address[] memory requiredDVNs = new address[](4); 
                requiredDVNs[0] = layerZero_sepolia;
                requiredDVNs[1] = gcp;
                requiredDVNs[2] = nethermind_testnet_ethereum;
                requiredDVNs[3] = nethermind_mainnet;
        
        configBytes = abi.encode(confirmations, requiredDVNCount, optionalDVNCount, optionalDVNThreshold, requiredDVNs, optionalDVNs);

        // params
        SetConfigParam memory param1 = SetConfigParam({
            eid: remoteChainID,     // dstEid
            configType: 2,
            config: configBytes
        });

        // array of params
        SetConfigParam[] memory configParams = new SetConfigParam[](1);
        configParams[0] = param1;
        
        //call endpoint
        address endPointAddress = homeLzEP;
        address oappAddress = mocaTokenAdapterAddress;

        ILayerZeroEndpointV2(endPointAddress).setConfig(oappAddress, send302, configParams);
        ILayerZeroEndpointV2(endPointAddress).setConfig(oappAddress, receive302, configParams);

        vm.stopBroadcast();
    }
}*/