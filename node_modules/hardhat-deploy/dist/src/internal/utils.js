"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.bnReplacer = void 0;
function bnReplacer(k, v) {
    if (typeof v === 'bigint') {
        return v.toString();
    }
    return v;
}
exports.bnReplacer = bnReplacer;
//# sourceMappingURL=utils.js.map