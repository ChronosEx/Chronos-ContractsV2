const { ethers } = require("hardhat")
const { BigNumber } = require("ethers");

const MATURITY_PRECISION = BigNumber.from("1000000000000000000");
const MATURITY_INCREMENT = 3628800;
const ENTRY_CALCULATION_PRECISION = BigNumber.from("1000000000000000000");

module.exports.MATURITY_PRECISION = MATURITY_PRECISION;
module.exports.MATURITY_INCREMENT = MATURITY_INCREMENT;

module.exports.increaseTime = async function(seconds) {
    await ethers.provider.send("evm_increaseTime", [seconds])
}

module.exports.mintAndDeposit = async function(account, amount, _token, maNFT) {
    await _token.connect(account).mint(amount);
    await _token.connect(account).approve(maNFT.address, amount);
    await maNFT.connect(account).deposit(amount);
    let id = await maNFT.totalSupply();
    return id;
}

module.exports.mintAndDepositTo = async function(account, to, amount, _token, maNFT) {
    await _token.connect(account).mint(amount);
    await _token.connect(account).approve(maNFT.address, amount);
    await maNFT.connect(account).depositTo(amount, to.address);
    let id = await maNFT.totalSupply();
    return id;
}

module.exports.mint = async function(account, amount, _token) {
    await _token.connect(account).mint(amount);
}

module.exports.depositAll = async function(account, _token, maNFT) {
    let balance = await _token.balanceOf(account.address);
    await _token.connect(account).approve(maNFT.address, balance);
    await maNFT.connect(account).deposit(balance)
    let id = await maNFT.totalSupply();
    return id;
}

module.exports.increase = async function(account, id, amount, _token, maNFT) {
    await _token.connect(account).mint(amount);
    await _token.connect(account).approve(maNFT.address, amount);
    await maNFT.connect(account).increase(id, amount);
}

module.exports.split = async function(account, id, weights, maNFT) {
    await maNFT.connect(account).split(id, weights);
}

module.exports.merge = async function(account, idFrom, idTo, maNFT) {
    await maNFT.connect(account).merge(idFrom, idTo);
}

module.exports.withdraw = async function(account, id, maNFT) {
    await maNFT.connect(account).withdraw(id);
}

module.exports.withdrawAll = async function(account, maNFT) {
    await maNFT.connect(account).withdrawAll();
}

module.exports.sync = async function(account, maNFT) {
    await maNFT.connect(account).sync();
}

module.exports.multiplier = function multiplier(entry, currentTime) {
    let maturity = BigNumber.from(currentTime).sub(entry);

    if (maturity >= MATURITY_INCREMENT * 2) return BigNumber.from(3).mul(MATURITY_PRECISION);
    else return (BigNumber.from(maturity).mul(MATURITY_PRECISION).div(MATURITY_INCREMENT)).add(MATURITY_PRECISION);
}

module.exports.calculateNewEntry = function(oldAmount, newAmount, oldEntry, newEntry) {
    let olderEntry = BigNumber.from(Math.max(oldEntry, newEntry));
    let entryDiff = BigNumber.from(Math.max(oldEntry, newEntry)).sub(BigNumber.from(Math.min(oldEntry, newEntry)));
    let result = ((olderEntry.mul(ENTRY_CALCULATION_PRECISION)).sub((entryDiff.mul(newAmount).mul(ENTRY_CALCULATION_PRECISION)).div(oldAmount.add(newAmount)))).div(ENTRY_CALCULATION_PRECISION);
    
    return result;
}