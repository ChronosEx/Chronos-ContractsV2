const { expect } = require("chai");
const chai = require("chai");
const { BigNumber } = require("ethers");

const { MATURITY_PRECISION } = require("./helpers.js");

const { BN }  = require('bn.js');

chai.use(require('chai-bn')(BN));

module.exports.testError = function(expectedTotalWeight, totalWeight) {
    // it is expected to have an error in weight increment due to the maturity precision
    // and inprecision caused by epoch multipliers
    let error = expectedTotalWeight.sub(totalWeight);
    let errorInToken = error.div(MATURITY_PRECISION);
    let errorBN = new BN(errorInToken.toString());

    let precision = BigNumber.from(totalWeight).mul(100).div(expectedTotalWeight);
    console.log("Total weight precision = %" + precision);

    expect(errorBN).to.be.a.bignumber.that.is.greaterThan(new BN("-1"));
    expect(new BN(precision.toString())).to.be.a.bignumber.that.is.greaterThan(new BN("95"));
    
    return 100 - precision;
}