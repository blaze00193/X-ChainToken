# Setup

forge init
copy package.json
forge test
npm install
update foundry.toml for remmapings

## Sphinx

- Install Sphinx CLI: `npm install --save-dev @sphinx-labs/plugins`
- Install Sphinx Foundry fork: `npx sphinx install`
- Update .gitignore: `node_modules/`
- Add remapping: `@sphinx-labs/contracts/=lib/sphinx/packages/contracts/contracts/foundry`
- Update your deployment script
- propose:`npx sphinx propose script/DeploySphinx.s.sol --networks testnets --tc ContractName`

## Testnet Deployments

V1: Deploy.s.sol

- MocaToken: https://sepolia.etherscan.io/address/0x9cb6dc4b71e285e26cbb0605f94b4031fe04c72c#readContract
- MocaTokenAdaptor: https://sepolia.etherscan.io/address/0x4114eccadf3b248da9eee7d8df2d3ba6bb02cbcd#readContract
- MocaOFT: https://mumbai.polygonscan.com/address/0x8bb305df680eda14e6b25b975bf1a8831acf69ab#events

V2: DeployMock.s.sol (has unrestricted mint function)

- MocaTokenMock: https://sepolia.etherscan.io/address/0xd70ee3ee58394d5dac6ccc05bb917081a5ce2ab1
- MocaTokenAdaptor: https://sepolia.etherscan.io/address/0xc8011cb9cfca55b822e56dd048dc960abd6424ce#code
- MocaOFT: https://mumbai.polygonscan.com/address/0x7d7b79b59ffb5c684a8bad8fb1729aaa27883dde

## Sphinx Questions

- now that I have deployed these bunch of contracts, across mumbai and arb_sepolia, are they all operating from the same gnosis safe?
- how to continue to script through that safe in the future? (esp. after multiple iterations/deployments)
- reject deployment: cos' i used the wrong signer (phantom -> MM). Just redo and overwrite?
