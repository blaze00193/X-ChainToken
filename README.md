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