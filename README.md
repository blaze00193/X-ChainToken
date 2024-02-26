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


# Questions

- now that I have deployed these bunch of contracts, across mumbai and arb_sepolia, are they all operating from the same gnosis safe?
- how to continue to script through that safe in the future? (esp. after multiple iterations/deployments)
- reject deployment: cos' i used the wrong signer (phantom -> MM). Just redo and overwrrite?
- 