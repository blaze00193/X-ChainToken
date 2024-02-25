"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.UnknownSignerError = void 0;
const utils_1 = require("./internal/utils");
class UnknownSignerError extends Error {
    constructor(data) {
        super(`Unknown Signer for account: ${data.from} Trying to execute the following::\n ${JSON.stringify(data, utils_1.bnReplacer, '  ')}`);
        this.data = data;
        Error.captureStackTrace(this, UnknownSignerError);
    }
}
exports.UnknownSignerError = UnknownSignerError;
//# sourceMappingURL=errors.js.map