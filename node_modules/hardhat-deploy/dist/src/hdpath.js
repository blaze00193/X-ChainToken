"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getDerivationPath = void 0;
/* eslint-disable @typescript-eslint/no-explicit-any */
const chalk_1 = __importDefault(require("chalk"));
function logError(...args) {
    console.log(chalk_1.default.red(...args));
}
function getDerivationPath(chainId) {
    let coinType;
    switch (chainId) {
        case 1:
        case 2020 /* Ronin Mainnet */:
        case 2021 /* Ronin Testnet */:
            coinType = '60';
            break;
        case 3:
        case 4:
        case 5:
            coinType = '1';
            break;
        default:
            logError(`Network with chainId: ${chainId} not supported.`);
            return undefined;
    }
    const derivationPath = `m/44'/${coinType}'/0'/0`;
    return derivationPath;
}
exports.getDerivationPath = getDerivationPath;
//# sourceMappingURL=hdpath.js.map