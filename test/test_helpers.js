const { expect } = require("chai");
const chai = require("chai");
const { BigNumber } = require("ethers");

const { MATURITY_PRECISION } = require("./helpers.js");

const { BN }  = require('bn.js');

chai.use(require('chai-bn')(BN));

module.exports.testError = function(expectedTotalWeight, totalWeight) {
    // it is expected to have an error in weight increment due to the maturity precision
    let error = expectedTotalWeight.sub(totalWeight);
    let errorInToken = error.div(MATURITY_PRECISION);

    let acceptableError = new BN("100000000000") // 0.000001

    let errorBN = new BN(errorInToken.toString());

    expect(errorBN).to.be.a.bignumber.that.is.greaterThan(new BN("-1"));
    expect(errorBN).to.be.a.bignumber.that.is.lessThan(acceptableError);

    return errorInToken;
}