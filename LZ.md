# LZ call

- oftv2 is for endpoint v1
- @layerzerolabs/lz-evm-oapp-v2/ which is v2, has oft this is the latest version that works with Endpoints v2.
-- [LayerZero-v2](https://github.com/LayerZero-Labs/LayerZero-v2)

There is also the dev tools repo: [devTools](https://github.com/LayerZero-Labs/devtools/blob/main/examples/oft/contracts/mocks/MyOFTMock.sol)

- supporting scripts and examples

## LayerZero v2 works with OZ v5

- if you wanna extend with permit, be sure to audit

## Oapp: blocking/non-Blocking

- Oapp will be nonBlocking cos the order is irrelevant to us.
- By default, the LZv2 uses unordered delivery (non-blocking)

default is nonblocking.
but destination is ordered receival.

## What happens on messaging failure?

- Do we need to intervene at all? Or the messaging is retried continuously by the LZ relayers?
- Btw can we get some kind of monitoring dashboard: health metrics, downtime, failure tracking, etc
- So from our end, we are aware if something is done, where the issue might be.

> LZscan. thats it for now.
> process of writing API and scan SDK to get state of txns.
> api is quarter away
> see: https://layerzeroscan.com/tools

## Token concerns

- SMLJ PRECIME
- insecure params for default: gasLimits, etc
- don't deploy natively, user adaptor
- fixed supply & precrime invariant enforcing (token supply invariant)
- rateLimiting: maxSupply transferred within a window

### Offchain tracking support

- bot reading events to ensure supply not exceeded
- sound alert, pause
- what if we have our own DVN? i don't think it helps in this instance

### Emergency

- pause bridging
- pause the deployed token contracts on dest chains and the adaptor on home chain

### Misc

Only npm? can i install via submodules

npx create-lz-oapp@latest
- does not create a git repo. 

## When do we step in?

- confirmed on source
- check LZ, different messaging error status
- can check what they are, ask team what to do in those instances

## can list on stargate front-end

- form to fill up
- refer to traderJoe

## LZscna

- list dapp
- can see all txns
- for community
- got sdk to create alerts, etc health stuff

## shared marketing

- stargate listing
- lzscan listing
- commbo marketing

## xchain

- asptos
- cosmos
- solana
